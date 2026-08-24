import Foundation
import Network
import UIKit
import OSLog
import Combine

/// Drives the connection lifecycle for one Mac from the iPhone side,
/// including pausing for a pairing code when the Mac requires one and
/// automatically reconnecting (with backoff) if an established connection
/// drops unexpectedly. Owns a `RemoteConnection`, translates its outcome
/// into `ConnectionState`, and produces user-facing error messages rather
/// than raw `Error`s.
@MainActor
final class DeviceSessionViewModel: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .available
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var pairingCodeNeeded = false
    @Published private(set) var pairingErrorMessage: String?
    @Published private(set) var isSubmittingCode = false
    @Published private(set) var runningApplications: [RunningApplicationDescriptor] = []
    /// Progress detail while dialing a list of endpoints ("Trying over
    /// Internet…") so a multi-candidate connect doesn't look hung.
    @Published private(set) var connectProgressMessage: String?
    /// The endpoint that actually worked — video and file connections must
    /// dial the same address the control connection succeeded with, which
    /// is not necessarily the Bonjour endpoint when connecting from another
    /// network.
    @Published private(set) var activeEndpoint: NWEndpoint?

    private(set) var activeSession: SecureSession?
    private(set) var macDeviceID: UUID?

    private var connection: RemoteConnection?
    private var connectTask: Task<Void, Never>?
    private var pumpTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var lastMoveSentAt: Date?
    private static let moveThrottleInterval: TimeInterval = 1.0 / 60.0

    private static func isContinuousMotion(_ message: ProtocolMessage) -> Bool {
        switch message {
        case .mouseMove, .mouseDragged: return true
        default: return false
        }
    }
    private var lastEndpoint: NWEndpoint?
    private var lastDisplayName: String?
    /// All endpoints worth trying for the current Mac, in order. Reconnect
    /// walks this same list — e.g. if the Wi-Fi path died but the internet
    /// path still works, the session restores over the internet.
    private var candidateEndpoints: [NWEndpoint] = []

    func connect(to endpoint: NWEndpoint, displayName: String) {
        connect(to: endpoint, internetCandidates: [], displayName: displayName)
    }

    /// Dials each endpoint in turn — the live Bonjour/last-LAN endpoint
    /// first, then mesh-VPN, IPv6, and the router-mapped public address —
    /// and stops at the first one that gets far enough to either
    /// authenticate or ask for a pairing code. Every candidate is the same
    /// Mac (they all come from its own reports), so any success is a
    /// success. Failures accumulate into the visible error so a failed
    /// cross-network connect says exactly what was tried.
    func connect(to primary: NWEndpoint?, internetCandidates: [ConnectCandidate], displayName: String, primaryLabel: String = "Nearby (Bonjour)") {
        guard connectionState != .connecting, connectionState != .connected, connectionState != .reconnecting else { return }

        struct Attempt {
            let endpoint: NWEndpoint
            let label: String
        }
        var attempts: [Attempt] = []
        if let primary {
            attempts.append(Attempt(endpoint: primary, label: primaryLabel))
        }
        for candidate in internetCandidates {
            if let port = NWEndpoint.Port(rawValue: candidate.port) {
                attempts.append(Attempt(
                    endpoint: .hostPort(host: NWEndpoint.Host(candidate.host), port: port),
                    label: candidate.label
                ))
            }
        }
        guard !attempts.isEmpty else { return }

        var seen = Set<NWEndpoint>()
        attempts = attempts.filter { seen.insert($0.endpoint).inserted }
        candidateEndpoints = attempts.map(\.endpoint)
        lastEndpoint = attempts.first?.endpoint
        lastDisplayName = displayName
        connectionState = .connecting
        lastErrorMessage = nil
        connectProgressMessage = nil
        pairingCodeNeeded = false
        pairingErrorMessage = nil

        connectTask = Task {
            var attempted: [String] = []
            for (index, attempt) in attempts.enumerated() {
                guard !Task.isCancelled, connectionState == .connecting else { return }

                connectProgressMessage = index > 0 ? "Trying \(attempt.label)…" : nil

                let newConnection = RemoteConnection()
                do {
                    let result = try await newConnection.connect(to: attempt.endpoint, connectionTimeout: 6)
                    // The user may have cancelled while we were dialing.
                    guard !Task.isCancelled, connectionState == .connecting else {
                        await newConnection.close()
                        return
                    }
                    connection = newConnection
                    activeEndpoint = attempt.endpoint
                    connectProgressMessage = nil
                    handle(result: result, displayName: displayName)
                    return
                } catch {
                    await newConnection.close()
                    attempted.append("\(attempt.label) [\(Self.endpointHost(attempt.endpoint))]")
                    Logging.session.notice("Candidate \(attempt.label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            }

            guard !Task.isCancelled, connectionState == .connecting else { return }
            connectionState = .authenticationFailed
            connectProgressMessage = nil
            let tried = attempted.isEmpty ? "no known addresses" : "Tried " + attempted.joined(separator: ", ")
            lastErrorMessage = "Couldn't reach \(displayName). \(tried). Make sure the Mac is awake with Mac Remote open, and Tailscale is connected on both devices."
            Logging.session.error("All connection candidates failed for \(displayName, privacy: .public): \(tried, privacy: .public)")
        }
    }

    private static func endpointHost(_ endpoint: NWEndpoint) -> String {
        if case .hostPort(let host, let port) = endpoint {
            return "\(host):\(port)"
        }
        return "service"
    }

    func submitPairingCode(_ code: String) {
        guard let connection else { return }
        pairingErrorMessage = nil
        isSubmittingCode = true

        Task {
            do {
                let result = try await connection.submitPairingCode(code)
                self.isSubmittingCode = false
                self.handle(result: result, displayName: nil)
            } catch {
                self.isSubmittingCode = false
                self.pairingErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't complete pairing."
                Logging.session.error("Pairing failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func cancelPairing() {
        disconnect()
    }

    /// Fire-and-forget send for input (mouse/keyboard) — these are
    /// high-frequency and the UI has nothing useful to do with a
    /// per-message failure beyond noting it in the log. Requires an active,
    /// authenticated connection; silently does nothing otherwise.
    ///
    /// Continuous-motion messages (a finger dragging generates far more
    /// gesture callbacks than the network or the Mac's cursor needs) are
    /// throttled to ~60/sec; clicks, key presses, and everything else
    /// always send immediately and are never dropped.
    func sendInput(_ message: ProtocolMessage) {
        guard connectionState == .connected, let connection else { return }

        if Self.isContinuousMotion(message) {
            let now = Date()
            if let lastMoveSentAt, now.timeIntervalSince(lastMoveSentAt) < Self.moveThrottleInterval {
                return
            }
            lastMoveSentAt = now
        }

        Task {
            do {
                try await connection.send(message)
            } catch {
                Logging.input.error("Failed to send input: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Reads the local pasteboard and sends it to the Mac. Explicit and
    /// user-triggered by design — iOS shows a system permission prompt for
    /// *programmatic, unprompted* pasteboard reads, but treats a read that
    /// happens directly in response to the user tapping something as an
    /// ordinary user action. Continuous background polling of the iPhone's
    /// clipboard would hit that prompt repeatedly, so this app doesn't do
    /// that — see SECURITY.md.
    func sendClipboardToMac() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        sendInput(.clipboardUpdate(ClipboardPayload(text: text)))
    }

    func requestRunningApplications() {
        sendInput(.runningApplicationsRequest)
    }

    func activateApplication(_ application: RunningApplicationDescriptor) {
        sendInput(.activateApplication(ActivateApplicationPayload(bundleIdentifier: application.bundleIdentifier)))
    }

    /// Tears the connection down and returns to `.available`. Safe to call
    /// from any state, including mid-reconnect — this is also how the user
    /// cancels an in-progress automatic reconnection attempt.
    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        pumpTask?.cancel()
        pumpTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        let connectionToClose = connection
        connection = nil
        activeSession = nil
        macDeviceID = nil
        activeEndpoint = nil
        candidateEndpoints = []
        Task { await connectionToClose?.close() }
        connectionState = .available
        lastErrorMessage = nil
        connectProgressMessage = nil
        pairingCodeNeeded = false
        pairingErrorMessage = nil
        isSubmittingCode = false
        runningApplications = []
    }

    private func handle(result: RemoteConnection.ConnectResult, displayName: String?) {
        switch result {
        case .authenticated(let session, let macDeviceID, let macName, _):
            activeSession = session
            self.macDeviceID = macDeviceID
            pairingCodeNeeded = false
            lastErrorMessage = nil
            connectionState = .connected
            Logging.session.info("Connected to \(displayName ?? macName, privacy: .public)")
            startPumping()
        case .pairingCodeNeeded:
            pairingCodeNeeded = true
        }
    }

    /// Receives unsolicited messages from the Mac on the control
    /// connection — incoming clipboard updates, its current internet
    /// addresses (persisted for future cross-network connects), the running
    /// apps list, and detecting when the connection itself drops.
    private func startPumping() {
        guard let connection, pumpTask == nil else { return }
        pumpTask = Task {
            while !Task.isCancelled, let message = await connection.nextMessage() {
                switch message {
                case .clipboardUpdate(let payload) where SettingsStore.clipboardSyncEnabled:
                    UIPasteboard.general.string = payload.text
                case .clipboardUpdate:
                    break
                case .reachabilityUpdate(let payload):
                    if let macDeviceID {
                        TrustedDeviceStore().updateInternetEndpoints(deviceID: macDeviceID, payload: payload)
                    }
                case .runningApplications(let payload):
                    runningApplications = payload.applications
                default:
                    continue
                }
            }
            guard !Task.isCancelled else { return }
            self.pumpTask = nil
            self.handleUnexpectedDisconnect()
        }
    }

    /// The pump loop ended without `disconnect()` having been called —
    /// the connection dropped (Wi-Fi hiccup, Mac went to sleep, etc.)
    /// rather than the user leaving. Rather than dumping them back to
    /// "Tap to Connect," try to quietly restore the session — walking the
    /// same candidate list, so a Wi-Fi drop can transparently recover over
    /// the internet path.
    private func handleUnexpectedDisconnect() {
        guard connectionState == .connected, !candidateEndpoints.isEmpty else { return }
        let endpoints = candidateEndpoints
        Logging.session.notice("Connection lost unexpectedly; attempting to reconnect")
        connection = nil
        activeSession = nil
        activeEndpoint = nil
        connectionState = .reconnecting

        reconnectTask = Task {
            for attempt in 1...ReconnectPolicy.maxAttempts {
                guard !Task.isCancelled, self.connectionState == .reconnecting else { return }

                let delaySeconds = ReconnectPolicy.delay(forAttempt: attempt)
                try? await Task.sleep(for: .milliseconds(Int(delaySeconds * 1000)))
                guard !Task.isCancelled, self.connectionState == .reconnecting else { return }

                for endpoint in endpoints {
                    let newConnection = RemoteConnection()
                    if let result = try? await newConnection.connect(to: endpoint), case .authenticated = result {
                        self.connection = newConnection
                        self.activeEndpoint = endpoint
                        self.handle(result: result, displayName: self.lastDisplayName)
                        Logging.session.info("Session restored after \(attempt) attempt(s)")
                        return
                    }
                    await newConnection.close()
                    guard !Task.isCancelled, self.connectionState == .reconnecting else { return }
                }
            }

            guard !Task.isCancelled, self.connectionState == .reconnecting else { return }
            self.connectionState = .authenticationFailed
            self.lastErrorMessage = "Couldn't reconnect to Mac. Make sure it's awake with Mac Remote open, then try again."
        }
    }
}
