import Foundation

/// First message sent on a new connection, before any authentication.
/// Identifies the sender, the protocol version it speaks, and what the
/// connection is for. Contains no secrets — authentication (Phase 2) rides
/// on top of this handshake.
struct HelloPayload: Sendable, Equatable {
    let protocolVersion: UInt16
    let deviceID: UUID
    let deviceName: String
    let deviceModel: String
    let deviceKind: DeviceKind
    let channelPurpose: ChannelPurpose

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt16(protocolVersion)
        writer.writeUUID(deviceID)
        writer.writeString(deviceName)
        writer.writeString(deviceModel)
        writer.writeUInt8(deviceKind.rawValue)
        writer.writeUInt8(channelPurpose.rawValue)
    }

    static func decode(from reader: inout ByteReader) throws -> HelloPayload {
        let version = try reader.readUInt16()
        let id = try reader.readUUID()
        let name = try reader.readString()
        let model = try reader.readString()
        guard let kind = DeviceKind(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        guard let purpose = ChannelPurpose(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        return HelloPayload(protocolVersion: version, deviceID: id, deviceName: name, deviceModel: model, deviceKind: kind, channelPurpose: purpose)
    }
}
