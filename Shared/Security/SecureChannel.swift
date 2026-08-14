import Foundation

/// Serializes sealing/opening for one connection's `SecureSession` so
/// multiple independent producers can safely share it — e.g. a control
/// connection's main receive loop and a background feature (clipboard
/// forwarding) that both need to send on the same connection. Actor
/// isolation is what makes concurrent callers safe without each one
/// managing its own lock.
actor SecureChannel {
    private let transport: MessageTransport
    private var session: SecureSession

    init(transport: MessageTransport, session: SecureSession) {
        self.transport = transport
        self.session = session
    }

    func send(_ message: ProtocolMessage) async throws {
        let sealed = try session.seal(message.encodedInner())
        try await transport.send(.secureEnvelope(SealedPayload(counter: sealed.counter, combined: sealed.combined)))
    }
}
