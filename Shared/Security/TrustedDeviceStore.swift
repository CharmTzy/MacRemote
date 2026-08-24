import Foundation

/// Keychain-backed storage for paired devices. Unlike `KeychainStore`'s raw
/// get/set, this speaks in `PairedDeviceRecord`s and owns the JSON encoding
/// — records are small, low-frequency, and local-only, so `Codable`/JSON is
/// the right tool here even though the network protocol deliberately avoids
/// it (see PROTOCOL.md).
struct TrustedDeviceStore {
    private let keychain: KeychainStore

    init(service: String = "com.macremote.trusteddevices") {
        self.keychain = KeychainStore(service: service)
    }

    func all() -> [PairedDeviceRecord] {
        let accounts = (try? keychain.allAccounts()) ?? []
        return accounts.compactMap { account -> PairedDeviceRecord? in
            guard let data = try? keychain.get(account: account) else { return nil }
            return try? JSONDecoder().decode(PairedDeviceRecord.self, from: data)
        }
        .sorted { $0.pairedAt > $1.pairedAt }
    }

    func record(for deviceID: UUID) -> PairedDeviceRecord? {
        guard let data = try? keychain.get(account: deviceID.uuidString) else { return nil }
        return try? JSONDecoder().decode(PairedDeviceRecord.self, from: data)
    }

    func save(_ record: PairedDeviceRecord) throws {
        let data = try JSONEncoder().encode(record)
        try keychain.set(data, account: record.id.uuidString)
    }

    func updateNetworkMetadata(
        deviceID: UUID,
        ipv4Address: String?,
        broadcastAddress: String?,
        wakeMACAddress: String?
    ) {
        guard let existing = record(for: deviceID) else { return }
        let updated = PairedDeviceRecord(
            id: existing.id,
            name: existing.name,
            model: existing.model,
            publicKey: existing.publicKey,
            pairedAt: existing.pairedAt,
            lastKnownIPv4Address: ipv4Address ?? existing.lastKnownIPv4Address,
            lastKnownBroadcastAddress: broadcastAddress ?? existing.lastKnownBroadcastAddress,
            wakeMACAddress: wakeMACAddress ?? existing.wakeMACAddress,
            lastKnownWANIPv4Address: existing.lastKnownWANIPv4Address,
            lastKnownExternalPort: existing.lastKnownExternalPort,
            knownIPv6Addresses: existing.knownIPv6Addresses
        )
        try? save(updated)
    }

    /// Persists the internet-reachable endpoints a Mac reported about itself
    /// (`reachabilityUpdate`), so future connections can dial it from any
    /// network. Values that are nil leave what's already stored in place.
    func updateInternetEndpoints(deviceID: UUID, payload: ReachabilityUpdatePayload) {
        guard var updated = record(for: deviceID) else { return }
        if let wan = payload.wanIPv4Address, !wan.isEmpty {
            updated.lastKnownWANIPv4Address = wan
        }
        if let port = payload.externalPort {
            updated.lastKnownExternalPort = port
        }
        if !payload.ipv6Addresses.isEmpty {
            updated.knownIPv6Addresses = payload.ipv6Addresses
        }
        if !payload.vpnIPv4Addresses.isEmpty {
            updated.knownVPNAddresses = ConnectCandidateBuilder.dedupedVPNIPv4(payload.vpnIPv4Addresses)
        }
        if let wakeMAC = payload.wakeMACAddress, !wakeMAC.isEmpty {
            updated.wakeMACAddress = wakeMAC
        }
        try? save(updated)
    }

    func remove(deviceID: UUID) throws {
        try keychain.delete(account: deviceID.uuidString)
    }

    func removeAll() throws {
        for account in (try? keychain.allAccounts()) ?? [] {
            try? keychain.delete(account: account)
        }
    }
}
