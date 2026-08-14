import Foundation

/// A key-code-level press or release, with modifiers — navigation/editing
/// keys, function keys, and shortcuts (a letter plus ⌘/⌥/⌃/⇧).
struct SpecialKeyPayload: Sendable, Equatable {
    let key: SpecialKey
    let modifiers: KeyModifiers
    let isDown: Bool

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt8(key.rawValue)
        writer.writeUInt8(modifiers.rawValue)
        writer.writeBool(isDown)
    }

    static func decode(from reader: inout ByteReader) throws -> SpecialKeyPayload {
        guard let key = SpecialKey(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        let modifiers = KeyModifiers(rawValue: try reader.readUInt8())
        return SpecialKeyPayload(key: key, modifiers: modifiers, isDown: try reader.readBool())
    }
}
