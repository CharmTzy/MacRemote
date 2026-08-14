import Foundation

/// Literal text to type, injected as Unicode on the Mac side rather than
/// mapped through virtual key codes — handles autocorrect, emoji, and any
/// script correctly regardless of keyboard layout, at the cost of not
/// being usable for shortcuts (see `SpecialKeyPayload` for those).
struct TextInputPayload: Sendable, Equatable {
    let text: String

    func encode(into writer: inout ByteWriter) {
        writer.writeString(text)
    }

    static func decode(from reader: inout ByteReader) throws -> TextInputPayload {
        TextInputPayload(text: try reader.readString())
    }
}
