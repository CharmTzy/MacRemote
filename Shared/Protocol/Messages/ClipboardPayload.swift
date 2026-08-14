import Foundation

/// One clipboard's text content — used both directions on the control
/// connection. URLs travel as plain text (a URL is valid text; the
/// receiving side's pasteboard treats it as a link the same as if it had
/// been copied there directly).
struct ClipboardPayload: Sendable, Equatable {
    let text: String

    func encode(into writer: inout ByteWriter) {
        writer.writeString(text)
    }

    static func decode(from reader: inout ByteReader) throws -> ClipboardPayload {
        ClipboardPayload(text: try reader.readString())
    }
}
