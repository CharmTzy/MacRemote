import Foundation

/// Sent after the last chunk. The receiver treats this as "the file is
/// exactly the bytes received so far" — there's no checksum, since both
/// ends are on the same LAN and TCP already guarantees byte-exact,
/// in-order delivery within a connection.
struct FileCompletePayload: Sendable, Equatable {
    let transferID: UUID

    func encode(into writer: inout ByteWriter) {
        writer.writeUUID(transferID)
    }

    static func decode(from reader: inout ByteReader) throws -> FileCompletePayload {
        FileCompletePayload(transferID: try reader.readUUID())
    }
}
