import Foundation

/// Sent by the iPhone on the video connection to switch which display is
/// being captured, without tearing down and re-authenticating the
/// connection. The Mac replies with a fresh `VideoConfig` for the new
/// display's resolution before frames from it start arriving.
struct SelectDisplayPayload: Sendable, Equatable {
    let displayID: UInt32

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt32(displayID)
    }

    static func decode(from reader: inout ByteReader) throws -> SelectDisplayPayload {
        SelectDisplayPayload(displayID: try reader.readUInt32())
    }
}
