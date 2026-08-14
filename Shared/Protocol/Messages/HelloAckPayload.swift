import Foundation

/// Response to `HelloPayload`. `accepted` will start carrying real meaning in
/// Phase 2 once the host can reject unpaired or unauthenticated devices; for
/// now the host always accepts so the transport and handshake can be
/// exercised end to end.
struct HelloAckPayload: Sendable, Equatable {
    let protocolVersion: UInt16
    let deviceID: UUID
    let deviceName: String
    let deviceModel: String
    let accepted: Bool
    let reason: String?

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt16(protocolVersion)
        writer.writeUUID(deviceID)
        writer.writeString(deviceName)
        writer.writeString(deviceModel)
        writer.writeBool(accepted)
        writer.writeString(reason ?? "")
    }

    static func decode(from reader: inout ByteReader) throws -> HelloAckPayload {
        let version = try reader.readUInt16()
        let id = try reader.readUUID()
        let name = try reader.readString()
        let model = try reader.readString()
        let accepted = try reader.readBool()
        let reason = try reader.readString()
        return HelloAckPayload(protocolVersion: version, deviceID: id, deviceName: name, deviceModel: model, accepted: accepted, reason: reason.isEmpty ? nil : reason)
    }
}
