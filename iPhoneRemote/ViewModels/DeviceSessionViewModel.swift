import Foundation
import Network

/// Drives the connection lifecycle for one Mac from the iPhone side. Owns a
/// `RemoteConnection`, translates its outcome into `ConnectionState`, and
/// produces a user-facing error message rather than a raw `Error`.
@MainActor
final class DeviceSessionViewModel: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .available
    @Published private(set) var lastErrorMessage: String?

    private var connection: RemoteConnection?
    private var connectTask: Task<Void, Never>?

    func connect(to endpoint: NWEndpoint, displayName: String) {
        guard connectionState != .connecting, connectionState != .connected else { return }
        connectionState = .connecting
        lastErrorMessage = nil

        let newConnection = RemoteConnection()
        connection = newConnection

        connectTask = Task {
            do {
                try await newConnection.connect(to: endpoint)
                self.connectionState = .connected
                Logging.session.info("Connected to \(displayName, privacy: .public)")
            } catch {
                self.connectionState = .authenticationFailed
                self.lastErrorMessage = "Couldn't Connect to Mac. Make sure both devices are on the same Wi-Fi network."
                Logging.session.error("Connect to \(displayName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func disconnect() {
        connectTask?.cancel()
        let connectionToClose = connection
        connection = nil
        Task { await connectionToClose?.close() }
        connectionState = .available
        lastErrorMessage = nil
    }
}
