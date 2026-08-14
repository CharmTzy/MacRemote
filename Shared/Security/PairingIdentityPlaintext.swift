import Foundation

/// The plaintext sealed inside an `identityExchange` message during
/// pairing. Never travels on the wire unencrypted — only its AES-GCM
/// ciphertext does (see `SealedPayload`).
struct PairingIdentityPlaintext {
    /// Raw Ed25519 public key (32 bytes).
    let publicKey: Data
    let deviceName: String
    let deviceModel: String

    func encode(into writer: inout ByteWriter) {
        writer.writeData(publicKey)
        writer.writeString(deviceName)
        writer.writeString(deviceModel)
    }

    func encoded() -> Data {
        var writer = ByteWriter()
        encode(into: &writer)
        return writer.data
    }

    static func decode(from data: Data) throws -> PairingIdentityPlaintext {
        var reader = ByteReader(data)
        return PairingIdentityPlaintext(
            publicKey: try reader.readData(),
            deviceName: try reader.readString(),
            deviceModel: try reader.readString()
        )
    }
}
