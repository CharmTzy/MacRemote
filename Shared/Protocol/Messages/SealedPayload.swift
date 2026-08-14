import Foundation

/// An AES-GCM sealed blob plus the counter it was sealed with. Used for two
/// purposes that share the same shape: the one-time identity exchange
/// during pairing, and every message sent after authentication completes
/// (`SecureSession` handles both the same way).
struct SealedPayload: Sendable, Equatable {
    let counter: UInt64
    let combined: Data

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt64(counter)
        writer.writeData(combined)
    }

    static func decode(from reader: inout ByteReader) throws -> SealedPayload {
        SealedPayload(counter: try reader.readUInt64(), combined: try reader.readData())
    }
}
