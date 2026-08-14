import Foundation

/// First message on a `.file`-purpose connection: announces an incoming
/// transfer before any chunk data. There's no accept/decline round trip —
/// both ends of this connection are already an authenticated, paired
/// device, so the receiver just starts writing.
struct FileOfferPayload: Sendable, Equatable {
    let transferID: UUID
    let filename: String
    let fileSize: UInt64

    func encode(into writer: inout ByteWriter) {
        writer.writeUUID(transferID)
        writer.writeString(filename)
        writer.writeUInt64(fileSize)
    }

    static func decode(from reader: inout ByteReader) throws -> FileOfferPayload {
        FileOfferPayload(transferID: try reader.readUUID(), filename: try reader.readString(), fileSize: try reader.readUInt64())
    }
}
