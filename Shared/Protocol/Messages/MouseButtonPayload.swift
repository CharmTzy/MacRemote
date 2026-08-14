import Foundation

/// A button press or release at a position — the start/end of a drag.
/// (A plain tap that isn't a drag is sent as `MouseClickPayload` instead,
/// so a simple click doesn't need two round trips.)
struct MouseButtonPayload: Sendable, Equatable {
    let position: NormalizedPoint
    let button: MouseButton
    let isDown: Bool

    func encode(into writer: inout ByteWriter) {
        position.encode(into: &writer)
        writer.writeUInt8(button.rawValue)
        writer.writeBool(isDown)
    }

    static func decode(from reader: inout ByteReader) throws -> MouseButtonPayload {
        let position = try NormalizedPoint.decode(from: &reader)
        guard let button = MouseButton(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        return MouseButtonPayload(position: position, button: button, isDown: try reader.readBool())
    }
}
