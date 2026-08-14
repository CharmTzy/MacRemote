import Foundation

/// Which authentication path a connection needs, decided by the Mac after
/// checking whether the connecting device's ID is in its trusted-device
/// store.
enum AuthMode: UInt8, Sendable {
    /// First-time connection: no trust record exists yet. Proceeds with
    /// code-confirmed pairing.
    case pairingRequired = 1
    /// Returning, already-paired device: proceeds with signature-based
    /// mutual authentication against the identity key recorded at pairing.
    case sessionAuth = 2
}
