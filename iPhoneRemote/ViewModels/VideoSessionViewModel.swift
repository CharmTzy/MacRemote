import Foundation
import Network
import CoreGraphics
import OSLog
import Combine

/// Opens the dedicated video connection to an already-paired Mac — the
/// exact same discovery/authentication machinery as the control
/// connection, just declared with `channelPurpose: .video` — and feeds
/// incoming frames to a `VideoDecoder`.
///
/// Also drives `.auto` quality: a ping every few seconds measures round
/// trip time over this same connection, feeds it to
/// `AdaptiveQualityController`, and applies the result the same way a
/// manual Settings change would (`VideoStreamer.applyQuality(_:)` on the
/// Mac doesn't know or care whether a profile change came from a person or
/// from this).
@MainActor
final class VideoSessionViewModel: ObservableObject {
    @Published private(set) var isStreaming = false
    @Published private(set) var errorMessage: String?
    /// The Mac's display size, from the most recent `VideoConfig` — needed
    /// to map a touch point to a normalized position (see
    /// `VideoContentGeometry`) while preserving the full display aspect ratio.
    @Published private(set) var videoSize: CGSize?
    @Published private(set) var availableDisplays: [DisplayDescriptor] = []
    @Published private(set) var selectedDisplayID: UInt32?

    let decoder = VideoDecoder()

    private var connection: RemoteConnection?
    private var pumpTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var adaptiveQuality = AdaptiveQualityController()
    private var appliedAutoProfile: QualityProfile = .balanced
    private var pendingPingTimestamp: UInt64?
    private var pendingPingSentAt: Date?

    func start(endpoint: NWEndpoint) {
        guard pumpTask == nil else { return }

        let newConnection = RemoteConnection()
        connection = newConnection

        pumpTask = Task {
            do {
                let result = try await newConnection.connect(to: endpoint, purpose: .video)
                guard case .authenticated = result else {
                    self.errorMessage = "This Mac needs to be paired again before it can stream video."
                    return
                }
                try? await newConnection.send(.qualityPreference(QualityPreferencePayload(profile: SettingsStore.streamingQuality)))
                self.startHeartbeat(over: newConnection)
                await self.pump(newConnection)
            } catch {
                self.errorMessage = "Couldn't start the video stream."
                Logging.session.error("Video connect failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func selectDisplay(_ id: UInt32) {
        guard let connection else { return }
        selectedDisplayID = id
        isStreaming = false
        Task {
            do {
                try await connection.send(.selectDisplay(SelectDisplayPayload(displayID: id)))
            } catch {
                Logging.session.error("Failed to switch display: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func changeQuality(_ profile: QualityProfile) {
        guard let connection else { return }
        Task {
            do {
                try await connection.send(.qualityPreference(QualityPreferencePayload(profile: profile)))
            } catch {
                Logging.session.error("Failed to change quality: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func stop() {
        pumpTask?.cancel()
        pumpTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pendingPingTimestamp = nil
        pendingPingSentAt = nil
        adaptiveQuality = AdaptiveQualityController()
        let connectionToClose = connection
        connection = nil
        isStreaming = false
        Task { await connectionToClose?.close() }
    }

    /// Pings every 3 seconds, but only when quality is `.auto` — a manual
    /// Quality choice means the person overrode automatic behavior, so
    /// this stays quiet rather than second-guessing them.
    private func startHeartbeat(over connection: RemoteConnection) {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                guard SettingsStore.streamingQuality == .auto else { continue }

                if self.pendingPingTimestamp != nil {
                    let profile = self.adaptiveQuality.recordTimeout()
                    self.applyAdaptiveProfileIfNeeded(profile, connection: connection)
                }

                let now = UInt64(Date().timeIntervalSince1970 * 1000)
                self.pendingPingTimestamp = now
                self.pendingPingSentAt = Date()
                try? await connection.send(.ping(now))
            }
        }
    }

    private func applyAdaptiveProfileIfNeeded(_ profile: QualityProfile, connection: RemoteConnection) {
        guard profile != appliedAutoProfile else { return }
        appliedAutoProfile = profile
        Logging.session.info("Auto quality switched to \(profile.label, privacy: .public)")
        Task {
            try? await connection.send(.qualityPreference(QualityPreferencePayload(profile: profile)))
        }
    }

    private func pump(_ connection: RemoteConnection) async {
        while !Task.isCancelled, let message = await connection.nextMessage() {
            switch message {
            case .videoConfig(let config):
                do {
                    try decoder.applyConfig(config)
                    videoSize = CGSize(width: Int(config.width), height: Int(config.height))
                    isStreaming = true
                    errorMessage = nil
                } catch {
                    errorMessage = "Couldn't configure the video decoder."
                    Logging.decoder.error("applyConfig failed: \(String(describing: error), privacy: .public)")
                }
            case .videoFrame(let frame):
                decoder.decode(frame)
            case .videoError(let videoError):
                errorMessage = videoError.reason
                isStreaming = false
            case .displayList(let list):
                availableDisplays = list.displays
                if selectedDisplayID == nil {
                    selectedDisplayID = list.displays.first(where: { $0.isMain })?.id ?? list.displays.first?.id
                }
            case .pong(let timestamp):
                guard pendingPingTimestamp == timestamp, let sentAt = pendingPingSentAt else { continue }
                pendingPingTimestamp = nil
                pendingPingSentAt = nil
                guard SettingsStore.streamingQuality == .auto else { continue }
                let profile = adaptiveQuality.recordRoundTrip(Date().timeIntervalSince(sentAt))
                applyAdaptiveProfileIfNeeded(profile, connection: connection)
            default:
                continue
            }
        }
        isStreaming = false
    }
}
