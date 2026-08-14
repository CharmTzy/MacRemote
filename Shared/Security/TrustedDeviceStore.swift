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

    func remove(deviceID: UUID) throws {
        try keychain.delete(account: deviceID.uuidString)
    }

    func removeAll() throws {
        for account in (try? keychain.allAccounts()) ?? [] {
            try? keychain.delete(account: account)
        }
    }
}
