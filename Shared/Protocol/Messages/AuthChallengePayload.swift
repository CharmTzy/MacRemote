import Foundation

/// The Mac's reply to `AuthBegin`: its own ephemeral public key, a fresh
/// nonce used as the HKDF salt for every key derived in this session, and
/// which authentication path to follow next.
///
/// `signature` is populated only for `.sessionAuth` (the Mac signing the
/// key-agreement transcript with its long-term identity key, so the iPhone
/// can detect a Mac impersonator before revealing anything). It's empty for
/// `.pairingRequired`, since there's no established trust yet to sign with.
struct AuthChallengePayload: Sendable, Equatable {
    let mode: AuthMode
    let ephemeralPublicKey: Data
    let nonce: Data
    let signature: Data

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt8(mode.rawValue)
        writer.writeData(ephemeralPublicKey)
        writer.writeData(nonce)
        writer.writeData(signature)
    }

    static func decode(from reader: inout ByteReader) throws -> AuthChallengePayload {
        guard let mode = AuthMode(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        return AuthChallengePayload(
            mode: mode,
            ephemeralPublicKey: try reader.readData(),
            nonce: try reader.readData(),
            signature: try reader.readData()
        )
    }
}
