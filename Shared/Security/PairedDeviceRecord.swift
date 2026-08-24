import Foundation

/// A trusted peer, recorded once at pairing time. This is the trust anchor
/// every later session is checked against — a session claiming this
/// `id` must prove it holds the private key matching `publicKey`, not just
/// know the UUID.
struct PairedDeviceRecord: Identifiable, Equatable {
    let id: UUID
    let name: String
    let model: String
    /// Raw Ed25519 public key (32 bytes), from `Curve25519.Signing.PublicKey.rawRepresentation`.
    let publicKey: Data
    let pairedAt: Date
    let lastKnownIPv4Address: String?
    let lastKnownBroadcastAddress: String?
    var wakeMACAddress: String?
    /// Internet-reachable endpoints learned from the Mac itself during a
    /// past session (`reachabilityUpdate`): its public IPv4, the router's
    /// mapped external port, and global IPv6 addresses. Lets a later
    /// connection attempt reach the Mac from outside its Wi-Fi even when
    /// Bonjour can't.
    var lastKnownWANIPv4Address: String?
    var lastKnownExternalPort: UInt16?
    var knownIPv6Addresses: [String]
    /// Mesh-VPN (Tailscale etc.) addresses — the most reliable cross-network
    /// path since they never change and need no router cooperation.
    var knownVPNAddresses: [String]

    init(
        id: UUID,
        name: String,
        model: String,
        publicKey: Data,
        pairedAt: Date,
        lastKnownIPv4Address: String? = nil,
        lastKnownBroadcastAddress: String? = nil,
        wakeMACAddress: String? = nil,
        lastKnownWANIPv4Address: String? = nil,
        lastKnownExternalPort: UInt16? = nil,
        knownIPv6Addresses: [String] = [],
        knownVPNAddresses: [String] = []
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.publicKey = publicKey
        self.pairedAt = pairedAt
        self.lastKnownIPv4Address = lastKnownIPv4Address
        self.lastKnownBroadcastAddress = lastKnownBroadcastAddress
        self.wakeMACAddress = wakeMACAddress
        self.lastKnownWANIPv4Address = lastKnownWANIPv4Address
        self.lastKnownExternalPort = lastKnownExternalPort
        self.knownIPv6Addresses = knownIPv6Addresses
        self.knownVPNAddresses = knownVPNAddresses
    }
}

extension PairedDeviceRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, model, publicKey, pairedAt
        case lastKnownIPv4Address, lastKnownBroadcastAddress, wakeMACAddress
        case lastKnownWANIPv4Address, lastKnownExternalPort, knownIPv6Addresses
        case knownVPNAddresses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // decodeIfPresent throughout so records written by older app
        // versions (before the internet-endpoint fields existed) still load.
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            model: try container.decode(String.self, forKey: .model),
            publicKey: try container.decode(Data.self, forKey: .publicKey),
            pairedAt: try container.decode(Date.self, forKey: .pairedAt),
            lastKnownIPv4Address: try container.decodeIfPresent(String.self, forKey: .lastKnownIPv4Address),
            lastKnownBroadcastAddress: try container.decodeIfPresent(String.self, forKey: .lastKnownBroadcastAddress),
            wakeMACAddress: try container.decodeIfPresent(String.self, forKey: .wakeMACAddress),
            lastKnownWANIPv4Address: try container.decodeIfPresent(String.self, forKey: .lastKnownWANIPv4Address),
            lastKnownExternalPort: try container.decodeIfPresent(UInt16.self, forKey: .lastKnownExternalPort),
            knownIPv6Addresses: try container.decodeIfPresent([String].self, forKey: .knownIPv6Addresses) ?? [],
            knownVPNAddresses: try container.decodeIfPresent([String].self, forKey: .knownVPNAddresses) ?? []
        )
    }
}

extension PairedDeviceRecord {
    /// Every dialable address we remember for this Mac, ordered the same way
    /// live snapshots are ordered by `ConnectCandidateBuilder`
    /// (LAN → VPN mesh → global IPv6 → WAN+mapped port).
    func connectCandidates() -> [ConnectCandidate] {
        ConnectCandidateBuilder.candidates(from: ReachabilitySnapshot(
            lanIPv4Address: lastKnownIPv4Address,
            wanIPv4Address: lastKnownWANIPv4Address,
            externalPort: lastKnownExternalPort,
            ipv6Addresses: knownIPv6Addresses,
            vpnIPv4Addresses: knownVPNAddresses
        ))
    }
}
