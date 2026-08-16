import Foundation

struct RunningApplicationDescriptor: Sendable, Equatable, Identifiable {
    let bundleIdentifier: String
    let name: String
    let iconPNGData: Data
    let isActive: Bool

    var id: String { bundleIdentifier }

    func encode(into writer: inout ByteWriter) {
        writer.writeString(bundleIdentifier)
        writer.writeString(name)
        writer.writeData(iconPNGData)
        writer.writeBool(isActive)
    }

    static func decode(from reader: inout ByteReader) throws -> RunningApplicationDescriptor {
        RunningApplicationDescriptor(
            bundleIdentifier: try reader.readString(),
            name: try reader.readString(),
            iconPNGData: try reader.readData(),
            isActive: try reader.readBool()
        )
    }
}
