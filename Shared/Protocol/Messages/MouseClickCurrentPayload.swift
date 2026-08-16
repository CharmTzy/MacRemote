import Foundation

/// Clicks at the Mac's current cursor location. This pairs with relative
/// movement in Trackpad mode, where the iPhone intentionally does not keep
/// a second, drift-prone copy of the cursor's absolute position.
struct MouseClickCurrentPayload: Sendable, Equatable {
    let button: MouseButton
    let clickCount: UInt8

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt8(button.rawValue)
        writer.writeUInt8(clickCount)
    }

    static func decode(from reader: inout ByteReader) throws -> MouseClickCurrentPayload {
        guard let button = MouseButton(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        return MouseClickCurrentPayload(button: button, clickCount: try reader.readUInt8())
    }
}
