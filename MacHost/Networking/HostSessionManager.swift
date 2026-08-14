import Foundation
import Network
import OSLog

/// Owns the Mac's listening socket: advertises this Mac over Bonjour,
/// accepts incoming control connections, and performs the Hello/HelloAck
/// handshake. Phase 1 accepts every well-formed Hello — pairing and
/// authentication (Phase 2) will make `handleHello` actually reject
/// untrusted devices.
@MainActor
final class HostSessionManager: ObservableObject {
    @Published private(set) var connectedPeers: [ConnectedPeer] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var lastError: String?

    private var listener: NWListener?
    private static let listenerQueue = DispatchQueue(label: "com.macremote.host.listener")

    func start() {
        guard listener == nil else { return }

        do {
            let newListener = try NWListener(using: NWParametersFactory.controlChannel(), on: ServiceConstants.defaultPort)

            var txt = NWTXTRecord()
            txt[ServiceConstants.TXTKey.deviceName] = .string(DeviceIdentity.localDeviceName)
            txt[ServiceConstants.TXTKey.modelIdentifier] = .string(DeviceIdentity.localDeviceModel)
            txt[ServiceConstants.TXTKey.protocolVersion] = .string(String(ProtocolVersion.current))

            newListener.service = NWListener.Service(
                name: DeviceIdentity.localDeviceName,
                type: ServiceConstants.bonjourType,
                txtRecord: txt
            )

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handleListenerState(state) }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.handleNewConnection(connection) }
            }

            newListener.start(queue: Self.listenerQueue)
            listener = newListener
        } catch {
            lastError = "Couldn't start listening for connections."
            Logging.network.error("Listener creation failed: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
        connectedPeers.removeAll()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isAdvertising = true
            lastError = nil
            Logging.discovery.info("Advertising \(ServiceConstants.bonjourType, privacy: .public) on port \(ServiceConstants.defaultControlPort)")
        case .failed(let error):
            isAdvertising = false
            lastError = "Couldn't advertise this Mac on the local network."
            Logging.discovery.error("Listener failed: \(String(describing: error), privacy: .public)")
        case .cancelled:
            isAdvertising = false
        case .setup, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let transport = MessageTransport(connection: connection)
        Logging.session.info("Incoming connection from \(connection.endpoint.debugDescription, privacy: .public)")

        Task { [weak self] in
            var acceptedDeviceID: UUID?
            let stream = await transport.events
            for await event in stream {
                guard let self else { return }
                switch event {
                case .ready:
                    continue
                case .message(let message):
                    guard case .hello(let hello) = message, acceptedDeviceID == nil else { continue }
                    acceptedDeviceID = hello.deviceID
                    await self.handleHello(hello, transport: transport)
                case .failed(let reason):
                    Logging.network.notice("Peer connection ended: \(reason, privacy: .public)")
                    if let id = acceptedDeviceID { self.removePeer(id: id) }
                    return
                case .cancelled:
                    if let id = acceptedDeviceID { self.removePeer(id: id) }
                    return
                }
            }
        }
    }

    private func handleHello(_ hello: HelloPayload, transport: MessageTransport) async {
        guard hello.deviceKind == .iPhone else {
            Logging.session.notice("Rejecting Hello from a non-iPhone device kind.")
            return
        }

        let ack = HelloAckPayload(
            protocolVersion: ProtocolVersion.current,
            deviceID: DeviceIdentity.localDeviceID(),
            deviceName: DeviceIdentity.localDeviceName,
            deviceModel: DeviceIdentity.localDeviceModel,
            accepted: true,
            reason: nil
        )

        do {
            try await transport.send(.helloAck(ack))
        } catch {
            Logging.network.error("Failed to send HelloAck: \(String(describing: error), privacy: .public)")
            return
        }

        let peer = ConnectedPeer(id: hello.deviceID, name: hello.deviceName, model: hello.deviceModel, connectedAt: Date(), state: .connected)
        connectedPeers.removeAll { $0.id == peer.id }
        connectedPeers.append(peer)
        Logging.session.info("Accepted session from \(hello.deviceName, privacy: .public)")
    }

    private func removePeer(id: UUID) {
        connectedPeers.removeAll { $0.id == id }
    }
}
