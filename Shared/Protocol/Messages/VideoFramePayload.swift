import Foundation

/// One encoded frame. `sampleData` is AVCC-framed (each NAL unit prefixed
/// with its own 4-byte big-endian length) exactly as `VTCompressionSession`
/// produces it — the decoder consumes the same framing directly, with no
/// Annex-B conversion in either direction.
struct VideoFramePayload: Sendable, Equatable {
    let isKeyFrame: Bool
    let sampleData: Data

    func encode(into writer: inout ByteWriter) {
        writer.writeBool(isKeyFrame)
        writer.writeData(sampleData)
    }

    static func decode(from reader: inout ByteReader) throws -> VideoFramePayload {
        VideoFramePayload(isKeyFrame: try reader.readBool(), sampleData: try reader.readData())
    }
}
