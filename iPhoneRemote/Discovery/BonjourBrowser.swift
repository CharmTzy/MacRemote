import Foundation
import Network
import OSLog

enum BrowserEvent: Sendable {
    case resultsChanged(Set<NWBrowser.Result>)
    case failed(String)
}

/// Wraps `NWBrowser` for the `_macremote._tcp` service and republishes
/// results as an `AsyncStream`, so `DiscoveryViewModel` doesn't have to deal
/// with Network.framework's completion-handler API directly.
actor BonjourBrowser {
    private var browser: NWBrowser?
    private var eventContinuation: AsyncStream<BrowserEvent>.Continuation?
    let events: AsyncStream<BrowserEvent>

    private static let queue = DispatchQueue(label: "com.macremote.discovery")

    init() {
        var continuation: AsyncStream<BrowserEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false

        let newBrowser = NWBrowser(for: .bonjour(type: ServiceConstants.bonjourType, domain: nil), using: parameters)
        newBrowser.stateUpdateHandler = { [weak self] state in
            guard case .failed(let error) = state else { return }
            Task { await self?.reportFailure(error) }
        }
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { await self?.reportResults(results) }
        }
        newBrowser.start(queue: Self.queue)
        browser = newBrowser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private func reportResults(_ results: Set<NWBrowser.Result>) {
        eventContinuation?.yield(.resultsChanged(results))
    }

    private func reportFailure(_ error: NWError) {
        Logging.discovery.error("Browse failed: \(error.debugDescription, privacy: .public)")
        eventContinuation?.yield(.failed(error.localizedDescription))
    }
}
