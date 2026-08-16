import Foundation

struct RunningApplicationsPayload: Sendable, Equatable {
    let applications: [RunningApplicationDescriptor]

    func encode(into writer: inout ByteWriter) {
        let limited = Array(applications.prefix(Int(UInt16.max)))
        writer.writeUInt16(UInt16(limited.count))
        for application in limited { application.encode(into: &writer) }
    }

    static func decode(from reader: inout ByteReader) throws -> RunningApplicationsPayload {
        let count = Int(try reader.readUInt16())
        var applications: [RunningApplicationDescriptor] = []
        applications.reserveCapacity(count)
        for _ in 0..<count {
            applications.append(try RunningApplicationDescriptor.decode(from: &reader))
        }
        return RunningApplicationsPayload(applications: applications)
    }
}
