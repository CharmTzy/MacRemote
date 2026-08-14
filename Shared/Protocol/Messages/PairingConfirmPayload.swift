import Foundation

/// `.pairingRequired` path only: an HMAC tag proving the sender derived the
/// same key from the pairing code as the other side. Sent by the iPhone
/// first (proving it knows the code the Mac is displaying), then by the Mac
/// in reply (proving the reverse) — see `PairingCrypto.confirmTag`'s
/// `context` parameter for how the two directions stay distinguishable.
struct PairingConfirmPayload: Sendable, Equatable {
    let confirmTag: Data

    func encode(into writer: inout ByteWriter) {
        writer.writeData(confirmTag)
    }

    static func decode(from reader: inout ByteReader) throws -> PairingConfirmPayload {
        PairingConfirmPayload(confirmTag: try reader.readData())
    }
}
