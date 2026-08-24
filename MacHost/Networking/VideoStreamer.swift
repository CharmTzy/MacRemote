import Foundation
import ScreenCaptureKit
import CoreMedia
import OSLog

/// Bridges screen capture and encoding to the network for one video
/// connection: owns a `ScreenCaptureSession` and `H264Encoder`, and pushes
/// `videoConfig`/`videoFrame`/`displayList` messages — sealed with the
/// connection's `SecureSession` — as encoded frames arrive. One instance
/// per video connection; stop it when the connection closes.
///
/// Also decodes incoming traffic on the same connection (`selectDisplay`)
/// — video is mostly one-directional, but display switching needs a way
/// back, and reusing this connection avoids a second handshake for it.
actor VideoStreamer {
    private let transport: MessageTransport
    private var session: SecureSession
    private var captureSession = ScreenCaptureSession()
    private var encoder: H264Encoder?
    private var currentDisplayID: CGDirectDisplayID?
    private var currentQuality: QualityProfile = .balanced

    init(transport: MessageTransport, session: SecureSession) {
        self.transport = transport
        self.session = session
    }

    func start() async {
        guard PermissionsChecker.isScreenRecordingGranted() else {
            await sendError("Screen Recording isn't allowed for Mac Remote yet. Grant it in the Permissions tab, then reconnect.")
            return
        }

        let displays = (try? await DisplayCatalog.availableDisplays()) ?? []
        await sendSealed(.displayList(DisplayListPayload(displays: displays.map {
            DisplayDescriptor(id: UInt32($0.id), width: UInt32($0.width), height: UInt32($0.height), isMain: $0.isMain, name: $0.name)
        })))

        guard let primary = displays.first(where: { $0.isMain }) ?? displays.first else {
            await sendError("No display is available to capture.")
            return
        }

        await startCapturing(displayID: primary.id)
    }

    /// Switches to a different display without tearing down the
    /// connection: stops the current capture/encoder and starts fresh
    /// against the new display, sending an updated `VideoConfig` for its
    /// resolution.
    func selectDisplay(id: CGDirectDisplayID) async {
        guard id != currentDisplayID else { return }
        await captureSession.stop()
        encoder?.stop()
        encoder = nil
        await startCapturing(displayID: id)
    }

    /// The Mac's displays just went to sleep. Capture produces no frames
    /// while they're off, so tell the iPhone why the picture froze instead
    /// of leaving it staring at a silent last frame — input keeps working.
    func handleDisplaySleep() async {
        await sendError("The Mac's display is asleep — video resumes when it wakes. Touch input still works.")
    }

    /// Displays are back (or the system woke): ScreenCaptureKit streams die
    /// with the display, so restart capture against the same display and
    /// send a fresh `VideoConfig` + keyframe to resync the decoder.
    func handleDisplayWake() async {
        guard let displayID = currentDisplayID else { return }
        Logging.capture.info("Restarting capture after display wake")
        await captureSession.stop()
        encoder?.stop()
        encoder = nil
        await startCapturing(displayID: displayID)
    }

    /// Applies a new quality profile (bitrate + frame rate target) by
    /// restarting capture/encoding against the currently-selected display.
    func applyQuality(_ profile: QualityProfile) async {
        guard profile != currentQuality, let displayID = currentDisplayID else {
            currentQuality = profile
            return
        }
        currentQuality = profile
        await captureSession.stop()
        encoder?.stop()
        encoder = nil
        await startCapturing(displayID: displayID)
    }

    /// Decrypts an incoming message on this same connection (the iPhone's
    /// uses for this so far are `selectDisplay`, `qualityPreference`, and
    /// `ping` for round-trip-time measurement — see `pong(_:)`).
    func decodeIncoming(_ sealed: SealedPayload) -> ProtocolMessage? {
        guard let plaintext = try? session.open(counter: sealed.counter, combined: sealed.combined) else { return nil }
        return try? ProtocolMessage.decodeInner(plaintext)
    }

    /// Replies to a `ping` immediately — the iPhone uses the round trip
    /// time to drive `.auto` quality (Phase 8's `AdaptiveQualityController`).
    func pong(_ timestamp: UInt64) async {
        await sendSealed(.pong(timestamp))
    }

    func stop() async {
        await captureSession.stop()
        encoder?.stop()
        encoder = nil
    }

    private func startCapturing(displayID: CGDirectDisplayID) async {
        guard let display = try? await DisplayCatalog.scDisplay(for: displayID) else {
            await sendError("That display is no longer available.")
            return
        }

        currentDisplayID = displayID
        captureSession = ScreenCaptureSession()
        let quality = currentQuality

        let newEncoder = H264Encoder(width: Int32(display.width), height: Int32(display.height))
        encoder = newEncoder

        do {
            try newEncoder.start(
                averageBitRate: quality.averageBitRate,
                expectedFrameRate: quality.frameRate,
                onParameterSets: { [weak self] sps, pps in
                    Task { await self?.sendConfig(width: display.width, height: display.height, sps: sps, pps: pps) }
                },
                onEncodedFrame: { [weak self] frame in
                    Task { await self?.sendFrame(frame) }
                }
            )
        } catch {
            Logging.encoder.error("Couldn't start encoder: \(String(describing: error), privacy: .public)")
            await sendError("Couldn't start the video encoder.")
            return
        }

        do {
            try await captureSession.start(
                display: display,
                frameRate: quality.frameRate,
                onFrame: { [weak self] pixelBuffer, timestamp in
                    Task { await self?.encodeFrame(pixelBuffer, timestamp: timestamp) }
                },
                onStopped: { [weak self] error in
                    guard let error else { return }
                    Task { await self?.handleCaptureStopped(error) }
                }
            )
        } catch {
            Logging.capture.error("Couldn't start capture: \(String(describing: error), privacy: .public)")
            await sendError("Couldn't start screen capture. Check Screen Recording permission in System Settings.")
        }
    }

    private func encodeFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        encoder?.encode(pixelBuffer, presentationTimeStamp: timestamp)
    }

    private func handleCaptureStopped(_ error: Error) async {
        Logging.capture.error("Capture stopped: \(String(describing: error), privacy: .public)")
        await sendError("Screen capture stopped unexpectedly.")
    }

    private func sendConfig(width: Int, height: Int, sps: Data, pps: Data) async {
        await sendSealed(.videoConfig(VideoConfigPayload(width: UInt32(width), height: UInt32(height), sps: sps, pps: pps)))
    }

    private func sendFrame(_ frame: H264Encoder.EncodedFrame) async {
        await sendSealed(.videoFrame(VideoFramePayload(isKeyFrame: frame.isKeyFrame, sampleData: frame.sampleData)))
    }

    private func sendError(_ reason: String) async {
        await sendSealed(.videoError(VideoErrorPayload(reason: reason)))
    }

    private func sendSealed(_ message: ProtocolMessage) async {
        do {
            let sealed = try session.seal(message.encodedInner())
            try await transport.send(.secureEnvelope(SealedPayload(counter: sealed.counter, combined: sealed.combined)))
        } catch {
            Logging.encoder.error("Failed to send video message: \(String(describing: error), privacy: .public)")
        }
    }
}
