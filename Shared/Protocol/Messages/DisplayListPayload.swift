import Foundation

/// Sent once a video connection starts streaming, and again if the set of
/// displays changes. Capped at 255 displays, which is not a real limit in
/// practice.
struct DisplayListPayload: Sendable, Equatable {
    let displays: [DisplayDescriptor]

    func encode(into writer: inout ByteWriter) {
        let clamped = displays.prefix(255)
        writer.writeUInt8(UInt8(clamped.count))
        for display in clamped {
            display.encode(into: &writer)
        }
    }

    static func decode(from reader: inout ByteReader) throws -> DisplayListPayload {
        let count = try reader.readUInt8()
        var displays: [DisplayDescriptor] = []
        displays.reserveCapacity(Int(count))
        for _ in 0..<count {
            displays.append(try DisplayDescriptor.decode(from: &reader))
        }
        return DisplayListPayload(displays: displays)
    }
}
