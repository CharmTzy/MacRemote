import Foundation

/// Sent once, right after a video connection authenticates (and again if
/// the source display or its resolution changes). Carries what the decoder
/// needs before it can make sense of any `VideoFramePayload`: the frame
/// size and the H.264 parameter sets describing how the stream is encoded.
struct VideoConfigPayload: Sendable, Equatable {
    let width: UInt32
    let height: UInt32
    /// Sequence Parameter Set, as produced by `CMVideoFormatDescriptionGetH264ParameterSetAtIndex`.
    let sps: Data
    /// Picture Parameter Set, same source.
    let pps: Data

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt32(width)
        writer.writeUInt32(height)
        writer.writeData(sps)
        writer.writeData(pps)
    }

    static func decode(from reader: inout ByteReader) throws -> VideoConfigPayload {
        VideoConfigPayload(
            width: try reader.readUInt32(),
            height: try reader.readUInt32(),
            sps: try reader.readData(),
            pps: try reader.readData()
        )
    }
}
