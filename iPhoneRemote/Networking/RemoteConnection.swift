import Foundation
import Network

/// Dials out to a Mac's control connection and performs the Hello/HelloAck
/// handshake. One instance per connection attempt — create a new one to
/// retry rather than reusing a failed connection.
actor RemoteConnection {
    enum ConnectionError: LocalizedError {
        case rejected(String)
        case connectionClosed
        case timedOut

        var errorDescription: String? {
            switch self {
            case .rejected(let reason): return reason
            case .connectionClosed: return "The connection closed unexpectedly."
            case .timedOut: return "The Mac didn't respond."
            }
        }
    }

    private var transport: MessageTransport?

    @discardableResult
    func connect(to endpoint: NWEndpoint) async throws -> HelloAckPayload {
        let transport = MessageTransport.connect(to: endpoint, parameters: NWParametersFactory.controlChannel())
        self.transport = transport

        let stream = await transport.events
        for await event in stream {
            switch event {
            case .ready:
                let hello = HelloPayload(
                    protocolVersion: ProtocolVersion.current,
                    deviceID: DeviceIdentity.localDeviceID(),
                    deviceName: DeviceIdentity.localDeviceName,
                    deviceModel: DeviceIdentity.localDeviceModel,
                    deviceKind: .iPhone
                )
                try await transport.send(.hello(hello))
            case .message(let message):
                guard case .helloAck(let ack) = message else { continue }
                if ack.accepted {
                    return ack
                } else {
                    throw ConnectionError.rejected(ack.reason ?? "The Mac declined the connection.")
                }
            case .failed(let reason):
                throw ConnectionError.rejected(reason)
            case .cancelled:
                throw ConnectionError.connectionClosed
            }
        }
        throw ConnectionError.connectionClosed
    }

    func close() async {
        await transport?.close()
        transport = nil
    }
}
