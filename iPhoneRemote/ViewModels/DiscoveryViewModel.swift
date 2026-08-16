import Foundation
import Network
import Combine

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var isSearching = false

    private let browser = BonjourBrowser()
    private let trustedDevices = TrustedDeviceStore()
    private var listenTask: Task<Void, Never>?

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
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        let browser = self.browser
        Task { await browser.stop() }
        isSearching = false
        discoveredMacs.removeAll()
    }

    private func applyResults(_ results: Set<NWBrowser.Result>) {
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

            return DiscoveredMac(
                id: deviceID?.uuidString ?? name,
                name: displayName,
                model: model,
                endpoint: result.endpoint,
                state: .available,
                deviceID: deviceID,
                ipv4Address: ipv4Address,
                broadcastAddress: broadcastAddress,
                wakeMACAddress: wakeMACAddress
            )
        }

        let liveIDs = Set(liveMacs.compactMap(\.deviceID))
        let rememberedMacs = trustedDevices.all().compactMap { record -> DiscoveredMac? in
            guard !liveIDs.contains(record.id), let host = record.lastKnownIPv4Address else { return nil }
            return DiscoveredMac(
                id: record.id.uuidString,
                name: record.name,
                model: record.model,
                endpoint: .hostPort(host: NWEndpoint.Host(host), port: ServiceConstants.defaultPort),
                state: .offline,
                deviceID: record.id,
                ipv4Address: host,
                broadcastAddress: record.lastKnownBroadcastAddress,
                wakeMACAddress: record.wakeMACAddress
            )
        }

        discoveredMacs = (liveMacs + rememberedMacs)
            .sorted { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state == .available }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
