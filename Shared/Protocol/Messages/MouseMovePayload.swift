import Foundation

/// Cursor moved without a button held (hover, or a finger moving before it
/// presses down in trackpad mode).
struct MouseMovePayload: Sendable, Equatable {
    let position: NormalizedPoint

    func encode(into writer: inout ByteWriter) {
        position.encode(into: &writer)
    }

    static func decode(from reader: inout ByteReader) throws -> MouseMovePayload {
        MouseMovePayload(position: try NormalizedPoint.decode(from: &reader))
    }
}
