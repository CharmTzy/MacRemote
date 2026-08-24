import Foundation

/// Reads primitive values back out of a buffer written by `ByteWriter`.
/// All reads are bounds-checked; malformed or truncated input throws rather
/// than trapping, since this data arrives over the network from a peer.
struct ByteReader {
    enum ReadError: Error {
        case outOfBounds
        case invalidUTF8
        case invalidUUID
        case invalidEnumRawValue
    }

    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var remainingBytes: Int { data.endIndex - offset }

    private mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.endIndex else {
            throw ReadError.outOfBounds
        }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }

    mutating func readUInt8() throws -> UInt8 {
        let bytes = try readBytes(1)
        return bytes[bytes.startIndex]
    }

    mutating func readBool() throws -> Bool {
        try readUInt8() != 0
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(2)
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }.bigEndian
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(4)
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readBytes(8)
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.bigEndian
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readFloat() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    mutating func readDouble() throws -> Double {
        Double(bitPattern: try readUInt64())
    }

    mutating func readString() throws -> String {
        let length = try readUInt16()
        let bytes = try readBytes(Int(length))
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw ReadError.invalidUTF8
        }
        return string
    }

    mutating func readData() throws -> Data {
        let length = try readUInt32()
        return try readBytes(Int(length))
    }

    /// Reads exactly `count` raw bytes without a length prefix. Used by
    /// fixed-layout third-party wire formats (e.g. PCP), not by our own.
    mutating func readRawBytes(_ count: Int) throws -> Data {
        try readBytes(count)
    }

    /// Skips `count` bytes. Counterpart to `writeRawData` for padding.
    mutating func discard(_ count: Int) throws {
        _ = try readBytes(count)
    }

    mutating func readUUID() throws -> UUID {
        guard let uuid = UUID(uuidString: try readString()) else {
            throw ReadError.invalidUUID
        }
        return uuid
    }
}
