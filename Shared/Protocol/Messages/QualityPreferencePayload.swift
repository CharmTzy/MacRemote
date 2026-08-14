import Foundation

/// Sent by the iPhone on the video connection — once at start, and again
/// whenever the user changes it in Settings — to request an encoding
/// quality. The Mac restarts capture/encoding at the new bitrate and frame
/// rate target (resolution stays native to the display either way).
struct QualityPreferencePayload: Sendable, Equatable {
    let profile: QualityProfile

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt8(profile.wireValue)
    }

    static func decode(from reader: inout ByteReader) throws -> QualityPreferencePayload {
        guard let profile = QualityProfile(wireValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        return QualityPreferencePayload(profile: profile)
    }
}
