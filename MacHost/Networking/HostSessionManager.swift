import Foundation
import Network
import OSLog
import Combine

/// Owns the Mac's listening socket: advertises this Mac over Bonjour,
/// accepts incoming control connections, and runs each one through the
/// Hello handshake and then `HostAuthenticator`. A connection that comes
/// out the other side authenticated gets its `SecureSession` kept alive for
/// the rest of the connection's lifetime, sealing every message from that
/// point on.
@MainActor
final class HostSessionManager: ObservableObject {
    @Published private(set) var connectedPeers: [ConnectedPeer] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var lastError: String?

    let pairingCoordinator: PairingCoordinator
    private let trustedDevices = TrustedDeviceStore()

    private var listener: NWListener?
    private static let listenerQueue = DispatchQueue(label: "com.macremote.host.listener")

    init(pairingCoordinator: PairingCoordinator = PairingCoordinator()) {
        self.pairingCoordinator = pairingCoordinator
    }

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

    /// Removes a paired device's trust record. It will need to pair again
    /// (with a fresh code) before it can connect.
    func forgetDevice(id: UUID) {
        try? trustedDevices.remove(deviceID: id)
        connectedPeers.removeAll { $0.id == id }
    }

    func forgetAllDevices() {
        try? trustedDevices.removeAll()
        connectedPeers.removeAll()
    }

    func pairedDevices() -> [PairedDeviceRecord] {
        trustedDevices.all()
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
            guard let self else { return }

            let stream = await transport.events
            var iterator = stream.makeAsyncIterator()

            guard let hello = await Self.awaitHello(&iterator) else {
                await transport.close()
                return
            }

            try? await transport.send(.helloAck(HelloAckPayload(
                protocolVersion: ProtocolVersion.current,
                deviceID: DeviceIdentity.localDeviceID(),
                deviceName: DeviceIdentity.localDeviceName,
                deviceModel: DeviceIdentity.localDeviceModel,
                accepted: true,
                reason: nil
            )))

            guard hello.deviceKind == .iPhone, hello.protocolVersion == ProtocolVersion.current else {
                await transport.close()
                return
            }

            let authenticator = HostAuthenticator(trustedDevices: self.trustedDevices, pairingCoordinator: self.pairingCoordinator)
            let outcome = await authenticator.authenticate(hello: hello, transport: transport, iterator: &iterator)

            switch outcome {
            case .authenticated(let session):
                switch hello.channelPurpose {
                case .control:
                    var mutableSession = session
                    self.registerPeer(hello)
                    await self.pumpAuthenticatedTraffic(deviceID: hello.deviceID, transport: transport, iterator: &iterator, session: &mutableSession)
                    self.removePeer(id: hello.deviceID)
                case .video:
                    await self.streamVideo(deviceID: hello.deviceID, transport: transport, session: session, iterator: &iterator)
                }
            case .rejected(let reason):
                Logging.session.notice("Rejected \(hello.deviceName, privacy: .public): \(reason, privacy: .public)")
                await transport.close()
            }
        }
    }

    /// Starts capturing and encoding once a video connection authenticates,
    /// and keeps it running until the connection closes. Video is one
    /// direction only (Mac → iPhone) — this loop's job is purely to notice
    /// disconnection so capture can stop promptly.
    private func streamVideo(
        deviceID: UUID,
        transport: MessageTransport,
        session: SecureSession,
        iterator: inout AsyncStream<TransportEvent>.Iterator
    ) async {
        let streamer = VideoStreamer(transport: transport, session: session)
        await streamer.start()
        Logging.session.info("Streaming video to \(deviceID.uuidString, privacy: .public)")

        while let event = await iterator.next() {
            switch event {
            case .failed, .cancelled:
                await streamer.stop()
                return
            case .ready, .message:
                continue
            }
        }
        await streamer.stop()
    }

    private static func awaitHello(_ iterator: inout AsyncStream<TransportEvent>.Iterator) async -> HelloPayload? {
        while let event = await iterator.next() {
            switch event {
            case .message(let message):
                if case .hello(let hello) = message { return hello }
            case .failed, .cancelled:
                return nil
            case .ready:
                continue
            }
        }
        return nil
    }

    /// Keeps a connection alive after authentication, decrypting any
    /// `secureEnvelope` traffic it sends. No feature sends anything over
    /// this yet (that starts in later phases) — this loop's job for now is
    /// just to detect disconnection and keep the peer's `SecureSession`
    /// ready for when one does.
    private func pumpAuthenticatedTraffic(
        deviceID: UUID,
        transport: MessageTransport,
        iterator: inout AsyncStream<TransportEvent>.Iterator,
        session: inout SecureSession
    ) async {
        while let event = await iterator.next() {
            switch event {
            case .message(let message):
                guard case .secureEnvelope(let sealed) = message else { continue }
                guard let plaintext = try? session.open(counter: sealed.counter, combined: sealed.combined),
                      let inner = try? ProtocolMessage.decodeInner(plaintext) else {
                    Logging.security.error("Dropping unreadable secure envelope from \(deviceID.uuidString, privacy: .public)")
                    continue
                }
                handleAuthenticatedMessage(inner, from: deviceID)
            case .failed, .cancelled:
                return
            case .ready:
                continue
            }
        }
    }

    /// Nothing decodes to a real feature yet on the control channel — video
    /// has its own dedicated connection and handler (`streamVideo`); input
    /// and keyboard (Phase 4/5) will decode here.
    private func handleAuthenticatedMessage(_ message: ProtocolMessage, from deviceID: UUID) {}

    private func registerPeer(_ hello: HelloPayload) {
        let peer = ConnectedPeer(id: hello.deviceID, name: hello.deviceName, model: hello.deviceModel, connectedAt: Date(), state: .connected)
        connectedPeers.removeAll { $0.id == peer.id }
        connectedPeers.append(peer)
        Logging.session.info("Authenticated session with \(hello.deviceName, privacy: .public)")
    }

    private func removePeer(id: UUID) {
        connectedPeers.removeAll { $0.id == id }
    }
}
