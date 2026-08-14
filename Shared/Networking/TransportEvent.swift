import Foundation

/// Lifecycle events surfaced by `MessageTransport` to whoever owns it.
enum TransportEvent: Sendable {
    case ready
    case message(ProtocolMessage)
    case failed(String)
    case cancelled
}
