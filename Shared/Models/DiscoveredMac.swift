import Foundation
import Network

/// A Mac found on the local network via Bonjour, as seen from the iPhone.
/// Distinct from a *paired* device record (Phase 2): this is just "we can
/// see it," independent of whether we trust it yet.
struct DiscoveredMac: Identifiable, Equatable, Hashable {
    /// Stable within a discovery session; derived from the Bonjour endpoint.
    let id: String
    let name: String
    let model: String?
    let endpoint: NWEndpoint
    var state: ConnectionState
    let deviceID: UUID?
    let ipv4Address: String?
    let broadcastAddress: String?
    let wakeMACAddress: String?

    init(
        id: String,
        name: String,
        model: String?,
        endpoint: NWEndpoint,
        state: ConnectionState,
        deviceID: UUID? = nil,
        ipv4Address: String? = nil,
        broadcastAddress: String? = nil,
        wakeMACAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.endpoint = endpoint
        self.state = state
        self.deviceID = deviceID
        self.ipv4Address = ipv4Address
        self.broadcastAddress = broadcastAddress
        self.wakeMACAddress = wakeMACAddress
    }

    static func == (lhs: DiscoveredMac, rhs: DiscoveredMac) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.model == rhs.model && lhs.state == rhs.state &&
            lhs.ipv4Address == rhs.ipv4Address && lhs.wakeMACAddress == rhs.wakeMACAddress
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
