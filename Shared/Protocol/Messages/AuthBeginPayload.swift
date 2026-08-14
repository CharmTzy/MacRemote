import Foundation

/// First message of the authentication phase, sent by the connecting
/// (dialing) device immediately after the Hello/HelloAck exchange.
struct AuthBeginPayload: Sendable, Equatable {
    /// Raw X25519 public key (32 bytes) for this session's ephemeral key agreement.
    let ephemeralPublicKey: Data

    func encode(into writer: inout ByteWriter) {
        writer.writeData(ephemeralPublicKey)
    }

    static func decode(from reader: inout ByteReader) throws -> AuthBeginPayload {
        AuthBeginPayload(ephemeralPublicKey: try reader.readData())
    }
}
