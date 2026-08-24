import Foundation
import Network
import CoreGraphics
import OSLog
import Combine
import AppKit

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
    @Published private(set) var activeTransfers: [UUID: FileTransferProgress] = [:]

    /// Keeps the system awake (display may sleep; system doesn't) so
    /// iPhones can connect any time the app is open — see its doc comment.
    let availabilityKeeper = SystemAvailabilityKeeper()
    /// Gathers and publishes this Mac's internet-reachable addresses.
    let reachability = ReachabilityController()

    let pairingCoordinator: PairingCoordinator
    private let trustedDevices = TrustedDeviceStore()
    private let clipboardMonitor = ClipboardMonitor()
    private var controlChannels: [UUID: SecureChannel] = [:]
    private var activeVideoStreamers: [VideoStreamer] = []
    private var workspaceObserverTokens: [NSObjectProtocol] = []

    private var listener: NWListener?
    private static let listenerQueue = DispatchQueue(label: "com.macremote.host.listener")

    /// True while the app wants to be reachable — gates auto-recovery.
    private var wantsRunning = false
    private let pathMonitor = NWPathMonitor()
    private var watchdogTask: Task<Void, Never>?
    /// Consecutive probes that failed to see our own Bonjour advertisement.
    private var missedAdvertisementProbes = 0
    /// Last seen mesh-VPN (Tailscale etc.) addresses, so the path monitor
    /// can detect a VPN interface appearing and rebuild the listener.
    private var lastKnownVPNInterfaces: [String] = []

    init(pairingCoordinator: PairingCoordinator? = nil) {
        self.pairingCoordinator = pairingCoordinator ?? PairingCoordinator()
        clipboardMonitor.onTextChanged = { [weak self] text in
            self?.broadcastClipboard(text)
        }
        observeRunningApplications()
        observeAvailabilityChanges()
    }

    func start() {
        guard listener == nil else { return }
        wantsRunning = true
        availabilityKeeper.begin()
        reachability.start()
        startPathMonitoring()
        startAdvertisementWatchdog()

        do {
            let parameters = NWParametersFactory.controlChannel()
            // Rebinding the same port right after a restart (watchdog or
            // wake) needs SO_REUSEADDR or macOS can hand back EADDRINUSE.
            parameters.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: parameters, on: ServiceConstants.defaultPort)

            var txt = NWTXTRecord()
            txt[ServiceConstants.TXTKey.deviceName] = DeviceIdentity.localDeviceName
            txt[ServiceConstants.TXTKey.modelIdentifier] = DeviceIdentity.localDeviceModel
            txt[ServiceConstants.TXTKey.protocolVersion] = String(ProtocolVersion.current)
            txt[ServiceConstants.TXTKey.deviceID] = DeviceIdentity.localDeviceID().uuidString
            if let network = LocalNetworkInfo.primaryInterface() {
                txt[ServiceConstants.TXTKey.ipv4Address] = network.ipv4Address
                txt[ServiceConstants.TXTKey.broadcastAddress] = network.broadcastAddress
                txt[ServiceConstants.TXTKey.wakeMACAddress] = network.macAddress
            }

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
            clipboardMonitor.start()
        } catch {
            lastError = "Couldn't start listening for connections."
            Logging.network.error("Listener creation failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Cancels only the listener — active iPhone sessions keep running.
    private func teardownListener() {
        listener?.cancel()
        listener = nil
    }

    /// Rebinds the socket and re-registers Bonjour. Used after sleep/wake,
    /// network changes, and whenever the watchdog notices the advertisement
    /// vanished (macOS can drop mDNS registration across interface changes
    /// even while the TCP socket is still perfectly alive).
    func restartAdvertising() {
        guard wantsRunning else { return }
        teardownListener()
        clipboardMonitor.stop()
        isAdvertising = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.start()
        }
    }

    func stop() {
        wantsRunning = false
        watchdogTask?.cancel()
        watchdogTask = nil
        pathMonitor.cancel()
        teardownListener()
        isAdvertising = false
        connectedPeers.removeAll()
        clipboardMonitor.stop()
        controlChannels.removeAll()
        reachability.stop()
    }

    private func broadcastClipboard(_ text: String) {
        guard SettingsStore.clipboardSyncEnabled else { return }
        for channel in controlChannels.values {
            Task { try? await channel.send(.clipboardUpdate(ClipboardPayload(text: text))) }
        }
    }

    private func observeRunningApplications() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification
        ] {
            workspaceObserverTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.broadcastRunningApplications() }
            })
        }
    }

    /// Reacts to display/system sleep and wake: video streams pause with an
    /// explanation while the screen is off, resume (capture restarted) when
    /// it comes back, and the published reachability snapshot is refreshed
    /// after any wake since addresses may have changed.
    private func observeAvailabilityChanges() {
        availabilityKeeper.onDisplaySleep = { [weak self] in
            let streamers = self?.activeVideoStreamers ?? []
            Task {
                for streamer in streamers {
                    await streamer.handleDisplaySleep()
                }
            }
        }
        availabilityKeeper.onWake = { [weak self] in
            guard let self else { return }
            // ScreenCaptureKit streams die with the display — rebuild them,
            // and refresh published addresses (they often change on wake).
            let streamers = self.activeVideoStreamers
            Task {
                for streamer in streamers {
                    await streamer.handleDisplayWake()
                }
            }
            self.reachability.refresh()
            // Bonjour registration frequently doesn't survive sleep/wake —
            // rebind the listener so the iPhone can see us again.
            self.restartAdvertising()
        }
        reachability.onSnapshotChanged = { [weak self] payload in
            guard let self else { return }
            Task {
                for channel in self.controlChannels.values {
                    try? await channel.send(.reachabilityUpdate(payload))
                }
            }
        }
    }

    private func sendRunningApplications(to deviceID: UUID) {
        guard let channel = controlChannels[deviceID] else { return }
        let payload = RunningApplicationsController.snapshot()
        Task { try? await channel.send(.runningApplications(payload)) }
    }

    private func broadcastRunningApplications() {
        let payload = RunningApplicationsController.snapshot()
        for channel in controlChannels.values {
            Task { try? await channel.send(.runningApplications(payload)) }
        }
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
            missedAdvertisementProbes = 0
            Logging.discovery.info("Advertising \(ServiceConstants.bonjourType, privacy: .public) on port \(ServiceConstants.defaultControlPort)")
        case .failed(let error):
            isAdvertising = false
            teardownListener()
            if case .posix(let code) = error, code == .EADDRINUSE {
                lastError = "Port 53511 is already in use — another Mac Remote copy may be running. Quit the other copy; this one will retry."
            } else {
                lastError = "Couldn't advertise this Mac on the local network — will keep retrying."
            }
            Logging.discovery.error("Listener failed: \(String(describing: error), privacy: .public); auto-retrying")
            scheduleRetryAfterFailure()
        case .cancelled:
            isAdvertising = false
        case .setup:
            break
        case .waiting(let error):
            // Waiting is recoverable (usually no network yet) — surface it
            // but don't tear anything down.
            Logging.discovery.notice("Listener waiting: \(String(describing: error), privacy: .public)")
        @unknown default:
            break
        }
    }

    /// A failed listener stays failed forever unless we act. Retry with a
    /// short delay for as long as the app wants to be reachable.
    private func scheduleRetryAfterFailure() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard self.wantsRunning, self.listener == nil else { return }
            self.start()
        }
    }

    /// Restarts advertising when the network path changes. Two cases:
    /// the listener died during an outage (restart when network returns),
    /// or a mesh-VPN interface (Tailscale etc.) appeared/disappeared — a
    /// listener created before the VPN came up doesn't accept connections
    /// on its address, so it must be rebuilt.
    private func startPathMonitoring() {
        lastKnownVPNInterfaces = LocalNetworkInfo.meshVPNIPv4Addresses()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.wantsRunning else { return }

                let vpn = LocalNetworkInfo.meshVPNIPv4Addresses()
                let vpnChanged = vpn != self.lastKnownVPNInterfaces
                self.lastKnownVPNInterfaces = vpn
                if vpnChanged {
                    Logging.discovery.notice("Mesh VPN interfaces changed (\(vpn.joined(separator: ","), privacy: .public)) — rebuilding listener")
                    self.restartAdvertising()
                    return
                }

                if path.status == .satisfied, !self.isAdvertising, self.listener == nil {
                    Logging.discovery.notice("Network path satisfied again — restarting listener")
                    self.start()
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.macremote.host.path"))
    }

    /// Belt-and-suspenders: every 20 s, browse for our own Bonjour service.
    /// macOS can silently drop a service's mDNS registration across Wi-Fi
    /// roams and interface changes while the TCP socket keeps working —
    /// from outside that looks identical to "app gone". Two consecutive
    /// misses trigger a full listener rebuild.
    private func startAdvertisementWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, !Task.isCancelled, self.wantsRunning, self.listener != nil else { continue }

                let seen = await Self.probeOwnAdvertisement()
                if seen || !self.isAdvertising && self.listener == nil {
                    // Either healthy, or already mid-recovery via .failed.
                    self.missedAdvertisementProbes = 0
                    continue
                }
                self.missedAdvertisementProbes += 1
                Logging.discovery.notice("Bonjour probe missed (\(self.missedAdvertisementProbes)/2)")
                if self.missedAdvertisementProbes >= 2 {
                    self.missedAdvertisementProbes = 0
                    Logging.discovery.notice("Advertisement lost — rebuilding listener")
                    self.restartAdvertising()
                }
            }
        }
    }

    /// Browses `_macremote._tcp` for up to 6 s looking for THIS Mac's own
    /// deviceID in the advertised TXT record.
    private static func probeOwnAdvertisement() async -> Bool {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: ServiceConstants.bonjourType, domain: nil), using: parameters)

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.macremote.host.watchdog")
            let myDeviceID = DeviceIdentity.localDeviceID().uuidString
            let state = QueueProtectedFlag()

            func finish(_ result: Bool) {
                guard state.tryFinish() else { return }
                browser.cancel()
                continuation.resume(returning: result)
            }

            browser.browseResultsChangedHandler = { results, _ in
                let mine = results.contains { result in
                    if case .bonjour(let txt) = result.metadata,
                       let id = txt[ServiceConstants.TXTKey.deviceID] {
                        return id == myDeviceID
                    }
                    return false
                }
                if mine { finish(true) }
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state { finish(false) }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 6) { finish(false) }
        }
    }

/// One-shot latch so the probe's completion can only resume once, from
/// whichever callback (result, failure, or timeout) wins the race.
private final class QueueProtectedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func tryFinish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
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
                    let channel = SecureChannel(transport: transport, session: session)
                    self.controlChannels[hello.deviceID] = channel
                    self.sendRunningApplications(to: hello.deviceID)
                    // Bring the iPhone up to date with this Mac's current
                    // addresses so it can reach us from other networks later.
                    if let payload = self.reachability.currentPayload() {
                        try? await channel.send(.reachabilityUpdate(payload))
                    }
                    await self.pumpAuthenticatedTraffic(deviceID: hello.deviceID, transport: transport, iterator: &iterator, session: &mutableSession)
                    self.removePeer(id: hello.deviceID)
                    self.controlChannels.removeValue(forKey: hello.deviceID)
                case .video:
                    await self.streamVideo(deviceID: hello.deviceID, transport: transport, session: session, iterator: &iterator)
                case .file:
                    await self.receiveFile(transport: transport, session: session, iterator: &iterator)
                }
            case .rejected(let reason):
                Logging.session.notice("Rejected \(hello.deviceName, privacy: .public): \(reason, privacy: .public)")
                await transport.close()
            }
        }
    }

    /// Receives one file transfer on a dedicated `.file` connection —
    /// iPhone → Mac only, see `FileReceiver`'s doc comment for why.
    private func receiveFile(
        transport: MessageTransport,
        session: SecureSession,
        iterator: inout AsyncStream<TransportEvent>.Iterator
    ) async {
        let receiver = FileReceiver(transport: transport, session: session)
        await receiver.receive(iterator: &iterator) { [weak self] progress in
            Task { @MainActor in self?.activeTransfers[progress.transferID] = progress }
        }
    }

    /// Starts capturing and encoding once a video connection authenticates,
    /// and keeps it running until the connection closes. Video is mostly
    /// one direction (Mac → iPhone), but this loop also decodes the
    /// occasional message back — `selectDisplay` and `qualityPreference`.
    private func streamVideo(
        deviceID: UUID,
        transport: MessageTransport,
        session: SecureSession,
        iterator: inout AsyncStream<TransportEvent>.Iterator
    ) async {
        let streamer = VideoStreamer(transport: transport, session: session)
        activeVideoStreamers.append(streamer)
        defer { activeVideoStreamers.removeAll { $0 === streamer } }
        await streamer.start()
        Logging.session.info("Streaming video to \(deviceID.uuidString, privacy: .public)")

        while let event = await iterator.next() {
            switch event {
            case .message(let message):
                guard case .secureEnvelope(let sealed) = message,
                      let inner = await streamer.decodeIncoming(sealed) else {
                    continue
                }
                switch inner {
                case .selectDisplay(let payload):
                    await streamer.selectDisplay(id: CGDirectDisplayID(payload.displayID))
                case .qualityPreference(let payload):
                    await streamer.applyQuality(payload.profile)
                case .ping(let timestamp):
                    await streamer.pong(timestamp)
                default:
                    break
                }
            case .failed, .cancelled:
                await streamer.stop()
                return
            case .ready:
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

    /// Video has its own dedicated connection and handler (`streamVideo`);
    /// everything else authenticated devices send arrives here.
    private func handleAuthenticatedMessage(_ message: ProtocolMessage, from deviceID: UUID) {
        switch message {
        case .mouseMove(let payload):
            MouseController.move(to: payload.position)
        case .mouseMoveRelative(let payload):
            MouseController.move(byX: payload.deltaX, deltaY: payload.deltaY)
        case .mouseButton(let payload):
            if payload.isDown {
                MouseController.buttonDown(at: payload.position, button: payload.button)
            } else {
                MouseController.buttonUp(at: payload.position, button: payload.button)
            }
        case .mouseDragged(let payload):
            MouseController.dragged(to: payload.position, button: payload.button)
        case .mouseClick(let payload):
            MouseController.click(at: payload.position, button: payload.button, count: payload.clickCount)
        case .mouseClickCurrent(let payload):
            MouseController.clickAtCurrentPosition(button: payload.button, count: payload.clickCount)
        case .scroll(let payload):
            MouseController.scroll(deltaX: payload.deltaX, deltaY: payload.deltaY)
        case .textInput(let payload):
            KeyboardController.typeText(payload.text)
        case .specialKey(let payload):
            KeyboardController.sendSpecialKey(payload.key, modifiers: payload.modifiers, isDown: payload.isDown)
        case .clipboardUpdate(let payload):
            guard SettingsStore.clipboardSyncEnabled else { return }
            clipboardMonitor.applyRemoteText(payload.text)
        case .systemCommand(let payload):
            SystemCommandController.perform(payload.command)
        case .runningApplicationsRequest:
            sendRunningApplications(to: deviceID)
        case .activateApplication(let payload):
            RunningApplicationsController.activate(bundleIdentifier: payload.bundleIdentifier) { [weak self] activated in
                if activated {
                    Logging.input.notice("Activated running application \(payload.bundleIdentifier, privacy: .public)")
                } else {
                    Logging.input.warning("Rejected application activation for \(payload.bundleIdentifier, privacy: .public)")
                }
                self?.broadcastRunningApplications()
            }
        default:
            break
        }
    }

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
