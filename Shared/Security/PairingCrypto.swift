import Foundation
import CryptoKit

/// Pure key-derivation math for pairing and session authentication — no
/// networking, no Keychain access, so it can be unit tested in isolation.
/// See SECURITY.md for what each derived key is for and the threat model
/// this design does and doesn't cover.
enum PairingCrypto {
    /// Derives the key both sides use to prove they were given the same
    /// human-entered pairing code, by folding the code into HKDF's
    /// `sharedInfo` rather than the input key material — this is the actual
    /// authentication step in code-based pairing (Method A). A party that
    /// doesn't know `code` cannot derive this key even if it observes or
    /// actively relays the ephemeral key exchange.
    static func pairingConfirmKey(sharedSecret: SharedSecret, code: String, nonce: Data) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: nonce,
            sharedInfo: Data("MacRemote-Pairing-Confirm-v1|\(code)".utf8),
            outputByteCount: 32
        )
    }

    /// Traffic key for the identity exchange that immediately follows a
    /// successful pairing confirmation. Deliberately a different key than
    /// `pairingConfirmKey` (different `sharedInfo`) so the confirmation MAC
    /// and the encryption key are cryptographically independent.
    static func pairingTrafficKey(sharedSecret: SharedSecret, code: String, nonce: Data) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: nonce,
            sharedInfo: Data("MacRemote-Pairing-Traffic-v1|\(code)".utf8),
            outputByteCount: 32
        )
    }

    /// Session key for a returning, already-paired device. No code involved
    /// — trust comes from the Ed25519 signature check against the public
    /// key recorded at pairing time, not from this derivation.
    static func sessionKey(sharedSecret: SharedSecret, nonce: Data) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: nonce,
            sharedInfo: Data("MacRemote-Session-v1".utf8),
            outputByteCount: 32
        )
    }

    /// HMAC confirmation tag. `context` distinguishes the two directions
    /// ("iphone-confirm" / "mac-confirm") so one side's tag can never be
    /// replayed back as the other's.
    static func confirmTag(key: SymmetricKey, context: String, transcript: Data) -> Data {
        var message = Data(context.utf8)
        message.append(transcript)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }
}
