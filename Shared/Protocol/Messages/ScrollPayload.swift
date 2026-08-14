import Foundation

/// A scroll-wheel delta. No position — scrolling acts on whatever's under
/// the current cursor position on the Mac, same as a real trackpad.
struct ScrollPayload: Sendable, Equatable {
    let deltaX: Float
    let deltaY: Float

    func encode(into writer: inout ByteWriter) {
        writer.writeFloat(deltaX)
        writer.writeFloat(deltaY)
    }

    static func decode(from reader: inout ByteReader) throws -> ScrollPayload {
        ScrollPayload(deltaX: try reader.readFloat(), deltaY: try reader.readFloat())
    }
}
