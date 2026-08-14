import Foundation
import Network
import OSLog
import Combine

/// Drives the connection lifecycle for one Mac from the iPhone side,
/// including pausing for a pairing code when the Mac requires one. Owns a
/// `RemoteConnection`, translates its outcome into `ConnectionState`, and
/// produces user-facing error messages rather than raw `Error`s.
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

    func connect(to endpoint: NWEndpoint, displayName: String) {
        guard connectionState != .connecting, connectionState != .connected else { return }
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
    func sendInput(_ message: ProtocolMessage) {
        guard connectionState == .connected, let connection else { return }
        Task {
            do {
                try await connection.send(message)
            } catch {
                Logging.input.error("Failed to send input: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func disconnect() {
        connectTask?.cancel()
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
            connectionState = .connected
            Logging.session.info("Connected to \(displayName ?? macName, privacy: .public)")
        case .pairingCodeNeeded:
            pairingCodeNeeded = true
        }
    }
}
