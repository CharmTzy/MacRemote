import Foundation

/// Cursor moved while `button` is held — the middle of a drag, between the
/// `MouseButtonPayload(isDown: true)` and `MouseButtonPayload(isDown: false)`
/// that bracket it. Kept distinct from `MouseMovePayload` because macOS
/// itself distinguishes `.leftMouseDragged` from `.mouseMoved` at the
/// `CGEvent` level, and some apps care about the difference.
struct MouseDraggedPayload: Sendable, Equatable {
    let position: NormalizedPoint
    let button: MouseButton

    func encode(into writer: inout ByteWriter) {
        position.encode(into: &writer)
        writer.writeUInt8(button.rawValue)
    }

    static func decode(from reader: inout ByteReader) throws -> MouseDraggedPayload {
        let position = try NormalizedPoint.decode(from: &reader)
        guard let button = MouseButton(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        return MouseDraggedPayload(position: position, button: button)
    }
}
