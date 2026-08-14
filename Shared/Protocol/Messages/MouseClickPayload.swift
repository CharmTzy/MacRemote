import Foundation

/// An atomic click — tap, double tap, or long-press-as-right-click — sent
/// as one message rather than a separate down/up pair, since the sender
/// already knows it's a complete click by the time it's recognized.
struct MouseClickPayload: Sendable, Equatable {
    let position: NormalizedPoint
    let button: MouseButton
    let clickCount: UInt8

    func encode(into writer: inout ByteWriter) {
        position.encode(into: &writer)
        writer.writeUInt8(button.rawValue)
        writer.writeUInt8(clickCount)
    }

    static func decode(from reader: inout ByteReader) throws -> MouseClickPayload {
        let position = try NormalizedPoint.decode(from: &reader)
        guard let button = MouseButton(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        return MouseClickPayload(position: position, button: button, clickCount: try reader.readUInt8())
    }
}
