import Foundation
import Network
import OSLog

/// Owns one `NWConnection` and speaks the framed `ProtocolMessage` wire
/// format over it. Used for both the accepting side (Mac host wraps an
/// incoming connection) and the dialing side (iPhone connects out).
///
/// All network callbacks land on a dedicated serial queue; actor isolation
/// is what makes it safe to touch this object from SwiftUI's main-actor code
/// without any manual locking.
actor MessageTransport {
    private let connection: NWConnection
    private var parser = FrameParser()
    private var eventContinuation: AsyncStream<TransportEvent>.Continuation?

    /// One event stream per transport. Intended for a single consumer, which
    /// matches how every call site here uses it (one owner reads events for
    /// the lifetime of the connection).
    let events: AsyncStream<TransportEvent>

    private static let queue = DispatchQueue(label: "com.macremote.transport")

    init(connection: NWConnection) {
        self.connection = connection
        var continuation: AsyncStream<TransportEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        Task { await self.start() }
    }

    static func connect(to endpoint: NWEndpoint, parameters: NWParameters) -> MessageTransport {
        MessageTransport(connection: NWConnection(to: endpoint, using: parameters))
    }

    private func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleState(state) }
        }
        connection.start(queue: Self.queue)
        receiveNext()
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            eventContinuation?.yield(.ready)
        case .failed(let error):
            Logging.network.error("Transport failed: \(error.debugDescription, privacy: .public)")
            eventContinuation?.yield(.failed(error.localizedDescription))
            eventContinuation?.finish()
        case .cancelled:
            eventContinuation?.yield(.cancelled)
            eventContinuation?.finish()
        case .setup, .preparing, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { await self?.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let data, !data.isEmpty {
            do {
                for message in try parser.feed(data) {
                    eventContinuation?.yield(.message(message))
                }
            } catch {
                Logging.network.error("Dropping connection after malformed frame: \(String(describing: error), privacy: .public)")
                eventContinuation?.yield(.failed("The connection sent malformed data."))
                eventContinuation?.finish()
                connection.cancel()
                return
            }
        }

        if let error {
            eventContinuation?.yield(.failed(error.localizedDescription))
            eventContinuation?.finish()
            return
        }

        if isComplete {
            eventContinuation?.yield(.cancelled)
            eventContinuation?.finish()
            return
        }

        receiveNext()
    }

    /// Sends one message. Throws if the underlying socket write fails; callers
    /// decide whether that means "retry" or "tear down the session".
    func send(_ message: ProtocolMessage) async throws {
        let frame = message.encodedFrame()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    func close() {
        eventContinuation?.finish()
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}
