import Foundation

/// Relative cursor movement in Mac display pixels. Trackpad mode uses this
/// instead of guessing an absolute cursor position, so it remains aligned
/// even if the Mac's physical trackpad moved the pointer between gestures.
struct MouseMoveRelativePayload: Sendable, Equatable {
    let deltaX: Float
    let deltaY: Float

    func encode(into writer: inout ByteWriter) {
        writer.writeFloat(deltaX)
        writer.writeFloat(deltaY)
    }

    static func decode(from reader: inout ByteReader) throws -> MouseMoveRelativePayload {
        MouseMoveRelativePayload(deltaX: try reader.readFloat(), deltaY: try reader.readFloat())
    }
}
