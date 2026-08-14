import Foundation

struct SystemCommandPayload: Sendable, Equatable {
    let command: SystemCommand

    func encode(into writer: inout ByteWriter) {
        writer.writeUInt8(command.rawValue)
    }

    static func decode(from reader: inout ByteReader) throws -> SystemCommandPayload {
        guard let command = SystemCommand(rawValue: try reader.readUInt8()) else {
            throw ByteReader.ReadError.invalidEnumRawValue
        }
        return SystemCommandPayload(command: command)
    }
}
