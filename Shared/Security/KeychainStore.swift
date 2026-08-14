import Foundation
import Security

/// Thin wrapper over a generic-password Keychain item. Used for anything
/// that must survive app reinstalls-within-the-same-device and must never
/// live in `UserDefaults`: the local device identity now, and pairing
/// key material / trusted-device records from Phase 2 onward.
///
/// Not a cache — every call hits the Keychain. Callers that need a value
/// frequently should hold onto it themselves after reading it once.
struct KeychainStore {
    enum KeychainError: Error {
        case unhandled(OSStatus)
    }

    let service: String

    /// - Parameter service: Keychain "service" string. Use one per logical
    ///   collection of items (e.g. `"com.macremote.identity"`,
    ///   `"com.macremote.trusteddevices"`) so items don't collide.
    init(service: String) {
        self.service = service
    }

    func set(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let searchQuery = baseQuery(account: account)
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandled(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unhandled(status)
        }
    }

    func get(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
        return result as? Data
    }

    func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    /// Every account under this service, e.g. every trusted device ID.
    func allAccounts() throws -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        query[kSecAttrAccount as String] = nil

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw KeychainError.unhandled(status)
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}
