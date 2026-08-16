import Foundation

struct ActivateApplicationPayload: Sendable, Equatable {
    let bundleIdentifier: String

    func encode(into writer: inout ByteWriter) {
        writer.writeString(bundleIdentifier)
    }

    static func decode(from reader: inout ByteReader) throws -> ActivateApplicationPayload {
        ActivateApplicationPayload(bundleIdentifier: try reader.readString())
    }
}
