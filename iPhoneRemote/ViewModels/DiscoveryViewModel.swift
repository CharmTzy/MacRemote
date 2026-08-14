import Foundation
import Network
import Combine

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var isSearching = false

    private let browser = BonjourBrowser()
    private var listenTask: Task<Void, Never>?

    func start() {
        guard listenTask == nil else { return }
        isSearching = true
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
        discoveredMacs = results.compactMap { result -> DiscoveredMac? in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }

            var displayName = name
            var model: String?
            if case .bonjour(let txt) = result.metadata {
                if case .string(let value)? = txt[ServiceConstants.TXTKey.deviceName] {
                    displayName = value
                }
                if case .string(let value)? = txt[ServiceConstants.TXTKey.modelIdentifier] {
                    model = value
                }
            }

            return DiscoveredMac(id: name, name: displayName, model: model, endpoint: result.endpoint, state: .available)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
