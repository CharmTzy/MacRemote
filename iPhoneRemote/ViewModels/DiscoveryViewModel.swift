import Foundation
import Network
import Combine

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var isSearching = false

    private let browser = BonjourBrowser()
    private let trustedDevices = TrustedDeviceStore()
    private let anywhereDirectory = AnywhereDirectory()
    private var listenTask: Task<Void, Never>?
    private var lastBrowseResults: Set<NWBrowser.Result> = []

    func start() {
        guard listenTask == nil else { return }
        isSearching = true
        applyResults([])
        listenTask = Task { [weak self] in
            await self?.browser.start()
            guard let stream = await self?.browser.events else { return }
            for await event in stream {
                guard let self else { return }
                switch event {
                case .resultsChanged(let results):
                    self.applyResults(results)
                case .failed:
                    self.isSearching = false
                }
            }
        }
        refreshAnywhereDirectory()
    }

    /// Fetches the iCloud reachability records for every paired Mac and
    /// re-renders the list with fresh internet candidates. Runs alongside
    /// Bonjour; failure here just means the list relies on remembered
    /// endpoints instead.
    func refreshAnywhereDirectory() {
        let pairedIDs = trustedDevices.all().map(\.id)
        Task { [weak self] in
            await self?.anywhereDirectory.refresh(for: pairedIDs)
            self?.applyResults(self?.lastBrowseResults ?? [])
        }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        let browser = self.browser
        Task { await browser.stop() }
        isSearching = false
        lastBrowseResults = []
        discoveredMacs.removeAll()
    }

    private func applyResults(_ results: Set<NWBrowser.Result>) {
        lastBrowseResults = results
        let liveMacs = results.compactMap { result -> DiscoveredMac? in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }

            var displayName = name
            var model: String?
            var deviceID: UUID?
            var ipv4Address: String?
            var broadcastAddress: String?
            var wakeMACAddress: String?
            if case .bonjour(let txt) = result.metadata {
                if let value = txt[ServiceConstants.TXTKey.deviceName] {
                    displayName = value
                }
                if let value = txt[ServiceConstants.TXTKey.modelIdentifier] {
                    model = value
                }
                deviceID = txt[ServiceConstants.TXTKey.deviceID].flatMap(UUID.init(uuidString:))
                ipv4Address = txt[ServiceConstants.TXTKey.ipv4Address]
                broadcastAddress = txt[ServiceConstants.TXTKey.broadcastAddress]
                wakeMACAddress = txt[ServiceConstants.TXTKey.wakeMACAddress]
            }

            if let deviceID {
                trustedDevices.updateNetworkMetadata(
                    deviceID: deviceID,
                    ipv4Address: ipv4Address,
                    broadcastAddress: broadcastAddress,
                    wakeMACAddress: wakeMACAddress
                )
            }

            // Even for a Mac that's visible right now, keep its internet
            // endpoints around — leaving Wi-Fi mid-session shouldn't strand
            // the connection.
            let candidates = internetCandidates(for: deviceID, lanIPv4: ipv4Address)

            return DiscoveredMac(
                id: deviceID?.uuidString ?? name,
                name: displayName,
                model: model,
                endpoint: result.endpoint,
                state: .available,
                deviceID: deviceID,
                ipv4Address: ipv4Address,
                broadcastAddress: broadcastAddress,
                wakeMACAddress: wakeMACAddress,
                internetCandidates: candidates
            )
        }

        let liveIDs = Set(liveMacs.compactMap(\.deviceID))
        let rememberedMacs = trustedDevices.all().compactMap { record -> DiscoveredMac? in
            guard !liveIDs.contains(record.id) else { return nil }
            let host = record.lastKnownIPv4Address
            let candidates = mergedCandidates(record: record, deviceID: record.id)
            guard !candidates.isEmpty else { return nil }

            return DiscoveredMac(
                id: record.id.uuidString,
                name: record.name,
                model: record.model,
                endpoint: .hostPort(host: NWEndpoint.Host(host ?? candidates[0].host), port: ServiceConstants.defaultPort),
                state: .offline,
                deviceID: record.id,
                ipv4Address: host,
                broadcastAddress: record.lastKnownBroadcastAddress,
                wakeMACAddress: record.wakeMACAddress,
                internetCandidates: candidates
            )
        }

        discoveredMacs = (liveMacs + rememberedMacs)
            .sorted { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state == .available }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func internetCandidates(for deviceID: UUID?, lanIPv4: String?) -> [ConnectCandidate] {
        guard let deviceID else { return [] }
        var snapshot = anywhereDirectory.snapshot(for: deviceID) ?? ReachabilitySnapshot()
        // Even for a Mac we can see right now, remember its mesh-VPN
        // address so cellular connections later dial it directly.
        if snapshot.vpnIPv4Addresses.isEmpty,
           let record = trustedDevices.record(for: deviceID) {
            snapshot.vpnIPv4Addresses = record.knownVPNAddresses
        }
        if snapshot.lanIPv4Address == nil { snapshot.lanIPv4Address = lanIPv4 }
        return ConnectCandidateBuilder.candidates(from: snapshot)
    }

    /// Fresh iCloud data first; anything it doesn't have falls back to what
    /// the Mac itself told us during past sessions (trust-store fields).
    private func mergedCandidates(record: PairedDeviceRecord, deviceID: UUID) -> [ConnectCandidate] {
        var snapshot = anywhereDirectory.snapshot(for: deviceID) ?? ReachabilitySnapshot(
            lanIPv4Address: record.lastKnownIPv4Address,
            wanIPv4Address: record.lastKnownWANIPv4Address,
            externalPort: record.lastKnownExternalPort,
            ipv6Addresses: record.knownIPv6Addresses,
            vpnIPv4Addresses: record.knownVPNAddresses
        )
        if snapshot.lanIPv4Address == nil { snapshot.lanIPv4Address = record.lastKnownIPv4Address }
        return ConnectCandidateBuilder.candidates(from: snapshot)
    }
}
