import Foundation

/// A trusted peer, recorded once at pairing time. This is the trust anchor
/// every later session is checked against — a session claiming this
/// `id` must prove it holds the private key matching `publicKey`, not just
/// know the UUID.
struct PairedDeviceRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let model: String
    /// Raw Ed25519 public key (32 bytes), from `Curve25519.Signing.PublicKey.rawRepresentation`.
    let publicKey: Data
    let pairedAt: Date
}
