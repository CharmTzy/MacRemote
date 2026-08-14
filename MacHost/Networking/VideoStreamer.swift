import Foundation
import ScreenCaptureKit
import CoreMedia
import OSLog

/// Bridges screen capture and encoding to the network for one video
/// connection: owns a `ScreenCaptureSession` and `H264Encoder`, and pushes
/// `videoConfig`/`videoFrame` messages — sealed with the connection's
/// `SecureSession` — as encoded frames arrive. One instance per video
/// connection; stop it when the connection closes.
actor VideoStreamer {
    private let transport: MessageTransport
    private var session: SecureSession
    private let captureSession = ScreenCaptureSession()
    private var encoder: H264Encoder?

    init(transport: MessageTransport, session: SecureSession) {
        self.transport = transport
        self.session = session
    }

    func start(frameRate: Int = 30) async {
        guard PermissionsChecker.isScreenRecordingGranted() else {
            await sendError("Screen Recording isn't allowed for Mac Remote yet. Grant it in the Permissions tab, then reconnect.")
            return
        }
        guard let display = try? await DisplayCatalog.primaryDisplay() else {
            await sendError("No display is available to capture.")
            return
        }

        let newEncoder = H264Encoder(width: Int32(display.width), height: Int32(display.height))
        encoder = newEncoder

        do {
            try newEncoder.start(
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
                frameRate: frameRate,
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

    func stop() async {
        await captureSession.stop()
        encoder?.stop()
        encoder = nil
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
