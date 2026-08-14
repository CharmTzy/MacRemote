import Foundation

/// One capturable display, as reported by the Mac. `id` round-trips back
/// in `SelectDisplayPayload` to request that display.
struct DisplayDescriptor: Sendable, Equatable, Identifiable {
    let id: UInt32
    let width: UInt32
    let height: UInt32
    let isMain: Bool
    let name: String

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt32(id)
        writer.writeUInt32(width)
        writer.writeUInt32(height)
        writer.writeBool(isMain)
        writer.writeString(name)
    }

    static func decode(from reader: inout ByteReader) throws -> DisplayDescriptor {
        DisplayDescriptor(
            id: try reader.readUInt32(),
            width: try reader.readUInt32(),
            height: try reader.readUInt32(),
            isMain: try reader.readBool(),
            name: try reader.readString()
        )
    }
}
