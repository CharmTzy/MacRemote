import Foundation

/// What a Mac knows about its own network addresses, in a form that can
/// travel to the iPhone two ways: as a `reachabilityUpdate` wire message
/// during any authenticated session (so the iPhone remembers it for later),
/// and as an iCloud record (so the iPhone can find the Mac with no prior
/// session from its current network).
///
/// None of this is secret — every field is already observable by anyone on
/// either network — and knowing these addresses grants nothing: sessions are
/// authenticated by Ed25519 signatures, not by network location.
struct ReachabilitySnapshot: Sendable, Equatable {
    /// The Mac's LAN IPv4 address, e.g. `192.168.1.20`. Only useful while
    /// both devices share that network.
    var lanIPv4Address: String?
    /// The home router's public IPv4 address.
    var wanIPv4Address: String?
    /// The external port the router maps to the Mac's control port. Equal
    /// to the internal port unless the router assigned a different one.
    var externalPort: UInt16?
    /// Global-scope IPv6 addresses of this Mac, if the ISP provides IPv6.
    var ipv6Addresses: [String]
    /// Mesh-VPN addresses (Tailscale etc., 100.64/10) — reachable from any
    /// network once both devices run the same VPN account, with no router
    /// configuration anywhere. The most reliable cross-network path when
    /// available.
    var vpnIPv4Addresses: [String]

    init(
        lanIPv4Address: String? = nil,
        wanIPv4Address: String? = nil,
        externalPort: UInt16? = nil,
        ipv6Addresses: [String] = [],
        vpnIPv4Addresses: [String] = []
    ) {
        self.lanIPv4Address = lanIPv4Address
        self.wanIPv4Address = wanIPv4Address
        self.externalPort = externalPort
        self.ipv6Addresses = ipv6Addresses
        self.vpnIPv4Addresses = vpnIPv4Addresses
    }
}

/// One dialable host:port the iPhone may try when connecting to a Mac that
/// Bonjour can't see (different network, Mac asleep-but-listening, etc.).
struct ConnectCandidate: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case lanIPv4
        case vpnMesh
        case wanIPv6
        case wanIPv4Mapped
    }

    let kind: Kind
    let host: String
    let port: UInt16

    var label: String {
        switch kind {
        case .lanIPv4: return "Local network"
        case .vpnMesh: return "Private network"
        case .wanIPv6: return "Internet (IPv6)"
        case .wanIPv4Mapped: return "Internet"
        }
    }
}

enum ConnectCandidateBuilder {
    /// Orders the ways an iPhone can attempt to reach one Mac, fastest and
    /// most reliable first:
    ///
    /// 1. LAN IPv4 — instant when both devices share Wi-Fi; fails fast
    ///    (seconds) when they don't.
    /// 2. Global IPv6 — bypasses NAT entirely when both sides have IPv6
    ///    (cellular always does), so it beats the mapped IPv4 path when
    ///    available.
    /// 3. Public IPv4 + router-mapped port — works wherever the router
    ///    accepted our port mapping.
    static func candidates(from snapshot: ReachabilitySnapshot) -> [ConnectCandidate] {
        var candidates: [ConnectCandidate] = []
        let port = snapshot.externalPort ?? ServiceConstants.defaultControlPort

        if let lan = sanitizedIPv4(snapshot.lanIPv4Address) {
            candidates.append(ConnectCandidate(kind: .lanIPv4, host: lan, port: ServiceConstants.defaultControlPort))
        }

        // Mesh-VPN addresses next: they work from any network and need no
        // router cooperation, so they beat every WAN path. On the same
        // Wi-Fi the LAN attempt above wins anyway.
        for address in dedupedVPNIPv4(snapshot.vpnIPv4Addresses) {
            candidates.append(ConnectCandidate(kind: .vpnMesh, host: address, port: ServiceConstants.defaultControlPort))
        }

        for address in dedupedGlobalIPv6(snapshot.ipv6Addresses) {
            candidates.append(ConnectCandidate(kind: .wanIPv6, host: address, port: ServiceConstants.defaultControlPort))
        }

        if let wan = sanitizedIPv4(snapshot.wanIPv4Address),
           // A private-range "public" address (CG-NAT, misreporting router)
           // can never accept inbound internet traffic — don't waste a
           // 6-second dial timeout on it.
           !isPrivateIPv4(wan) {
            candidates.append(ConnectCandidate(kind: .wanIPv4Mapped, host: wan, port: port))
        }

        return candidates
    }

    /// True when a string is a plausible dotted-quad IPv4 literal. Guards
    /// against empty/garbage values persisted from older sessions.
    static func sanitizedIPv4(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                  let octet = UInt8(part) else { return nil }
            // Reject zero-padded forms like "01" — harmless, but they make
            // equality comparisons messy.
            if part.count > 1 && part.hasPrefix("0") { return nil }
            _ = octet
        }
        return value
    }

    static func dedupedGlobalIPv6(_ addresses: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for address in addresses {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidGlobalIPv6(trimmed), seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    /// Keeps only plausible mesh-VPN (Tailscale etc.) addresses: dotted
    /// quads inside 100.64.0.0/10.
    static func dedupedVPNIPv4(_ addresses: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for address in addresses {
            guard let sanitized = sanitizedIPv4(address), isMeshVPNIPv4(sanitized),
                  seen.insert(sanitized).inserted else { continue }
            result.append(sanitized)
        }
        return result
    }

    /// True for 100.64.0.0/10 — the shared range Tailscale and other mesh
    /// VPNs assign to member devices.
    static func isMeshVPNIPv4(_ value: String) -> Bool {
        let octets = value.split(separator: ".").compactMap { UInt8($0) }
        return octets.count == 4 && octets[0] == 100 && (64...127).contains(octets[1])
    }

    /// True when an IPv4 address is private-range or CG-NAT — i.e. not a
    /// real internet-facing address. Used both to sanity-check what routers
    /// report as our "public" IP and to skip dialing remembered WAN
    /// addresses that could never accept inbound traffic.
    static func isPrivateIPv4(_ value: String?) -> Bool {
        guard let value else { return false }
        let octets = value.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return true }
        switch octets[0] {
        case 10:
            return true
        case 100:
            return (64...127).contains(octets[1]) // CGNAT 100.64/10
        case 172:
            return (16...31).contains(octets[1])
        case 192:
            return octets[1] == 168
        case 169:
            return octets[1] == 254 // link-local
        default:
            return false
        }
    }

    static func isValidGlobalIPv6(_ value: String) -> Bool {
        guard !value.isEmpty, value.contains(":") else { return false }
        var addr = in6_addr()
        guard value.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else { return false }
        // Link-local (fe80::/10), unique-local (fc00::/7), multicast
        // (ff00::/8), and loopback/unspecified are never reachable from
        // another network, so they're not worth a dial attempt.
        let lowered = value.lowercased()
        if lowered.hasPrefix("fe80:") || lowered.hasPrefix("fc") || lowered.hasPrefix("fd") ||
            lowered.hasPrefix("ff") || lowered == "::1" || lowered == "::" {
            return false
        }
        return true
    }
}
