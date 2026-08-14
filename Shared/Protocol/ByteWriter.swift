import Foundation

/// Appends primitive values to a growing byte buffer using a fixed, versioned
/// wire format (big-endian integers, length-prefixed strings/blobs).
///
/// This exists so the network protocol does not depend on `Codable`/JSON for
/// high-frequency messages (input, video). See PROTOCOL.md for the wire format.
struct ByteWriter {
    private(set) var data = Data()

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeBool(_ value: Bool) {
        writeUInt8(value ? 1 : 0)
    }

    mutating func writeUInt16(_ value: UInt16) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt32(_ value: UInt32) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt64(_ value: UInt64) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    mutating func writeInt32(_ value: Int32) {
        writeUInt32(UInt32(bitPattern: value))
    }

    mutating func writeFloat(_ value: Float) {
        writeUInt32(value.bitPattern)
    }

    mutating func writeDouble(_ value: Double) {
        writeUInt64(value.bitPattern)
    }

    /// Length-prefixed (UInt16 byte count) UTF-8 string. Callers must keep
    /// strings under 64KB; every current use (names, versions, paths) is well
    /// within that bound.
    mutating func writeString(_ value: String) {
        let utf8 = Data(value.utf8)
        writeUInt16(UInt16(clamping: utf8.count))
        data.append(utf8)
    }

    /// Length-prefixed (UInt32 byte count) opaque blob, for payloads that can
    /// legitimately be large (encrypted blobs, video frames, file chunks).
    mutating func writeData(_ value: Data) {
        writeUInt32(UInt32(clamping: value.count))
        data.append(value)
    }

    mutating func writeUUID(_ value: UUID) {
        writeString(value.uuidString)
    }
}
