import Foundation
import CryptoKit

/// This device's long-term Ed25519 signing identity — generated once on
/// first launch, stored in the Keychain, and never transmitted except as a
/// public key. Every future session with a paired peer is authenticated
/// against this key, which is why it lives in the Keychain
/// (`ThisDeviceOnly`, never iCloud-synced) rather than anywhere that could
/// be casually copied or backed up alongside the device it identifies.
///
/// This is distinct from `DeviceIdentity`'s plain UUID, which is just a
/// label. This key is what pairing actually trusts.
enum IdentityKeyManager {
    private static let keychain = KeychainStore(service: "com.macremote.identity")
    private static let privateKeyAccount = "longterm-signing-key"

    static func longTermPrivateKey() -> Curve25519.Signing.PrivateKey {
        if let stored = try? keychain.get(account: privateKeyAccount),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored) {
            return key
        }
        let newKey = Curve25519.Signing.PrivateKey()
        try? keychain.set(newKey.rawRepresentation, account: privateKeyAccount)
        return newKey
    }

    static var longTermPublicKey: Curve25519.Signing.PublicKey {
        longTermPrivateKey().publicKey
    }
}
