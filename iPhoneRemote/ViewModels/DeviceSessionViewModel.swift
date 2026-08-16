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

    func connect(to endpoint: NWEndpoint, displayName: String) {
        guard connectionState != .connecting, connectionState != .connected, connectionState != .reconnecting else { return }
        lastEndpoint = endpoint
        lastDisplayName = displayName
        connectionState = .connecting
        lastErrorMessage = nil
        pairingCodeNeeded = false
        pairingErrorMessage = nil

        let newConnection = RemoteConnection()
        connection = newConnection

        connectTask = Task {
            do {
                let result = try await newConnection.connect(to: endpoint)
                self.handle(result: result, displayName: displayName)
            } catch {
                self.connectionState = .authenticationFailed
                self.lastErrorMessage = "Couldn't Connect to Mac. Make sure both devices are on the same Wi-Fi network."
                Logging.session.error("Connect to \(displayName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
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

    /// Tears the connection down and returns to `.available`. Safe to call
    /// from any state, including mid-reconnect — this is also how the user
    /// cancels an in-progress automatic reconnection attempt.
    func disconnect() {
        connectTask?.cancel()
        pumpTask?.cancel()
        pumpTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        let connectionToClose = connection
        connection = nil
        activeSession = nil
        macDeviceID = nil
        Task { await connectionToClose?.close() }
        connectionState = .available
        lastErrorMessage = nil
        pairingCodeNeeded = false
        pairingErrorMessage = nil
        isSubmittingCode = false
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
    /// connection — incoming clipboard updates, and detecting when the
    /// connection itself drops. Writing to `UIPasteboard` from our own app
    /// isn't subject to the read-side permission prompt, so clipboard
    /// updates can be applied automatically.
    private func startPumping() {
        guard let connection, pumpTask == nil else { return }
        pumpTask = Task {
            while !Task.isCancelled, let message = await connection.nextMessage() {
                guard case .clipboardUpdate(let payload) = message, SettingsStore.clipboardSyncEnabled else { continue }
                UIPasteboard.general.string = payload.text
            }
            guard !Task.isCancelled else { return }
            self.pumpTask = nil
            self.handleUnexpectedDisconnect()
        }
    }

    /// The pump loop ended without `disconnect()` having been called —
    /// the connection dropped (Wi-Fi hiccup, Mac went to sleep, etc.)
    /// rather than the user leaving. Rather than dumping them back to
    /// "Tap to Connect," try to quietly restore the session.
    private func handleUnexpectedDisconnect() {
        guard connectionState == .connected, let endpoint = lastEndpoint else { return }
        Logging.session.notice("Connection lost unexpectedly; attempting to reconnect")
        connection = nil
        activeSession = nil
        connectionState = .reconnecting

        reconnectTask = Task {
            for attempt in 1...ReconnectPolicy.maxAttempts {
                guard !Task.isCancelled, self.connectionState == .reconnecting else { return }

                let delaySeconds = ReconnectPolicy.delay(forAttempt: attempt)
                try? await Task.sleep(for: .milliseconds(Int(delaySeconds * 1000)))
                guard !Task.isCancelled, self.connectionState == .reconnecting else { return }

                let newConnection = RemoteConnection()
                if let result = try? await newConnection.connect(to: endpoint), case .authenticated = result {
                    self.connection = newConnection
                    self.handle(result: result, displayName: self.lastDisplayName)
                    Logging.session.info("Session restored after \(attempt) attempt(s)")
                    return
                }
                await newConnection.close()
            }

            guard !Task.isCancelled, self.connectionState == .reconnecting else { return }
            self.connectionState = .authenticationFailed
            self.lastErrorMessage = "Couldn't reconnect to Mac. Make sure it's still on the same Wi-Fi network, then try again."
        }
    }
}
