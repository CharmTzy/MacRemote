import Foundation
import Network
import OSLog
import Combine

/// Owns this Mac's "reachable from anywhere" story: gathers its addresses,
/// asks the router to map the control port, publishes a snapshot to iCloud,
/// and hands the same snapshot to `HostSessionManager` so it can push
/// `reachabilityUpdate` to any iPhone already connected. Refreshed on start,
/// on network-path changes, and after system/display wake (addresses and
/// mappings often change across those events).
@MainActor
final class ReachabilityController: ObservableObject {
    enum Status: Equatable {
        case checking
        case active(summary: String)
        case degraded(summary: String)
        case unavailable(reason: String)
    }

    @Published private(set) var status: Status = .checking

    private let publisher = ReachabilityPublisher()
    private let pathMonitor = NWPathMonitor()
    private var refreshTask: Task<Void, Never>?
    private var lastPublishedSnapshot: ReachabilitySnapshot?
    /// `NWPathMonitor` can only be started once; restarts of the listener
    /// call `start()` again, so guard the monitor separately.
    private var didStartPathMonitor = false

    /// Called with every new snapshot — HostSessionManager forwards it to
    /// connected iPhones as a `reachabilityUpdate`.
    var onSnapshotChanged: ((ReachabilityUpdatePayload) -> Void)?

    private(set) var wakeMACAddress: String?

    func start() {
        if !didStartPathMonitor {
            didStartPathMonitor = true
            pathMonitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in self?.refresh() }
            }
            pathMonitor.start(queue: DispatchQueue(label: "com.macremote.reachability.path"))
        }
        refresh()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        pathMonitor.cancel()
        didStartPathMonitor = false
    }

    /// The most recently gathered snapshot, for sending to a newly
    /// connected iPhone. nil until the first gather completes.
    func currentPayload() -> ReachabilityUpdatePayload? {
        guard let snapshot = lastPublishedSnapshot else { return nil }
        return payload(from: snapshot)
    }

    func refresh() {
        guard refreshTask == nil || refreshTask?.isCancelled == true else { return }
        refreshTask = Task { [weak self] in
            await self?.gatherAndPublish()
            self?.refreshTask = nil
        }
    }

    private func gatherAndPublish() async {
        let lan = LocalNetworkInfo.primaryInterface()
        wakeMACAddress = lan?.macAddress
        let ipv6 = LocalNetworkInfo.globalIPv6Addresses()
        let vpnAddresses = LocalNetworkInfo.meshVPNIPv4Addresses()

        // Router port mapping. Renewal is just re-running this (~2× per lease).
        let mappingResult = await NATPortMapper.establishMapping(internalPort: ServiceConstants.defaultControlPort, lanIPv4: lan?.ipv4Address)

        var snapshot = ReachabilitySnapshot(
            lanIPv4Address: lan?.ipv4Address,
            wanIPv4Address: mappingResult.externalIP,
            externalPort: mappingResult.externalPort > 0 ? mappingResult.externalPort : nil,
            ipv6Addresses: ipv6,
            vpnIPv4Addresses: vpnAddresses
        )

        // Even without a router protocol, a user-configured manual port
        // forward makes WAN IP + default port valid — discover the public
        // IP so we can advertise it.
        if snapshot.wanIPv4Address == nil, !mappingResult.likelyBehindCarrierNAT {
            snapshot.wanIPv4Address = await NATPortMapper.publicIPOrFallback()
        }

        let changed = snapshot != lastPublishedSnapshot
        lastPublishedSnapshot = snapshot

        Logging.anywhere.info("Snapshot: lan=\(snapshot.lanIPv4Address ?? "-", privacy: .public) wan=\(snapshot.wanIPv4Address ?? "-", privacy: .public) port=\(snapshot.externalPort.map(String.init) ?? "-", privacy: .public) v6=\(snapshot.ipv6Addresses.count, privacy: .public) vpn=[\(snapshot.vpnIPv4Addresses.joined(separator: ","), privacy: .public)] method=\(mappingResult.method, privacy: .public)")

        updateStatus(snapshot: snapshot, mapping: mappingResult)

        guard changed else { return }
        do {
            try await publisher.publish(
                deviceID: DeviceIdentity.localDeviceID(),
                name: DeviceIdentity.localDeviceName,
                model: DeviceIdentity.localDeviceModel,
                snapshot: snapshot
            )
        } catch {
            Logging.anywhere.error("iCloud publish failed: \(String(describing: error), privacy: .public)")
            if case .active(let summary) = status {
                status = .degraded(summary: summary)
            }
        }

        onSnapshotChanged?(payload(from: snapshot))
    }

    private func payload(from snapshot: ReachabilitySnapshot) -> ReachabilityUpdatePayload {
        ReachabilityUpdatePayload(
            lanIPv4Address: snapshot.lanIPv4Address,
            wanIPv4Address: snapshot.wanIPv4Address,
            externalPort: snapshot.externalPort,
            ipv6Addresses: snapshot.ipv6Addresses,
            vpnIPv4Addresses: snapshot.vpnIPv4Addresses,
            wakeMACAddress: wakeMACAddress
        )
    }

    private func updateStatus(snapshot: ReachabilitySnapshot, mapping: NATMappingResult) {
        if let wan = snapshot.wanIPv4Address, let port = snapshot.externalPort, !NATPortMapper.looksPrivate(wan) {
            status = .active(summary: "\(wan):\(port) · \(mapping.method)")
        } else if !snapshot.vpnIPv4Addresses.isEmpty {
            // No router path, but the mesh VPN covers cross-network control.
            status = .active(summary: "Private network")
        } else if !snapshot.ipv6Addresses.isEmpty {
            status = .active(summary: "IPv6 direct")
        } else if let wan = snapshot.wanIPv4Address, snapshot.externalPort != nil {
            // Mapping exists but through carrier-grade NAT.
            status = .unavailable(reason: "Your internet provider uses CG-NAT, so connections from outside need IPv6 or a VPN.")
        } else if !publisher.isAvailable {
            status = .degraded(summary: "LAN only — iCloud unavailable")
        } else {
            status = .degraded(summary: "LAN only — router declined port mapping (enable UPnP)")
        }
    }
}
