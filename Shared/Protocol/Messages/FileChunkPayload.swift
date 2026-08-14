import Foundation

/// One chunk of file data. `offset` is redundant with simple in-order
/// delivery (TCP already guarantees ordering) but makes each chunk
/// self-describing, which is cheap insurance and useful for progress
/// reporting on the receiving end without tracking a running total by hand.
struct FileChunkPayload: Sendable, Equatable {
    let transferID: UUID
    let offset: UInt64
    let data: Data

    func encode(into writer: inout ByteWriter) {
        writer.writeUUID(transferID)
        writer.writeUInt64(offset)
        writer.writeData(data)
    }

    static func decode(from reader: inout ByteReader) throws -> FileChunkPayload {
        FileChunkPayload(transferID: try reader.readUUID(), offset: try reader.readUInt64(), data: try reader.readData())
    }
}
