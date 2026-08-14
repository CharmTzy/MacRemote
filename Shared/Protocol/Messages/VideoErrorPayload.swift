import Foundation

/// Sent on the video connection when the Mac can't start (or has to stop)
/// streaming — most commonly a missing Screen Recording permission. Lets
/// the iPhone show a real explanation instead of a silent black screen.
struct VideoErrorPayload: Sendable, Equatable {
    let reason: String

    func encode(into writer: inout ByteWriter) {
        writer.writeString(reason)
    }

    static func decode(from reader: inout ByteReader) throws -> VideoErrorPayload {
        VideoErrorPayload(reason: try reader.readString())
    }
}
