import XCTest
import Foundation

final class ByteWriterReaderTests: XCTestCase {
    func testPrimitiveRoundTrip() throws {
        var writer = ByteWriter()
        writer.writeUInt8(0xAB)
        writer.writeBool(true)
        writer.writeUInt16(0x1234)
        writer.writeUInt32(0xDEAD_BEEF)
        writer.writeUInt64(0x0123_4567_89AB_CDEF)
        writer.writeInt32(-42)
        writer.writeFloat(3.5)
        writer.writeDouble(2.71828)

        var reader = ByteReader(writer.data)
        XCTAssertEqual(try reader.readUInt8(), 0xAB)
        XCTAssertEqual(try reader.readBool(), true)
        XCTAssertEqual(try reader.readUInt16(), 0x1234)
        XCTAssertEqual(try reader.readUInt32(), 0xDEAD_BEEF)
        XCTAssertEqual(try reader.readUInt64(), 0x0123_4567_89AB_CDEF)
        XCTAssertEqual(try reader.readInt32(), -42)
        XCTAssertEqual(try reader.readFloat(), 3.5)
        XCTAssertEqual(try reader.readDouble(), 2.71828)
        XCTAssertEqual(reader.remainingBytes, 0)
    }

    func testStringAndDataRoundTrip() throws {
        var writer = ByteWriter()
        writer.writeString("Wai's MacBook Air")
        writer.writeData(Data([0x01, 0x02, 0x03, 0xFF]))
        writer.writeString("")

        var reader = ByteReader(writer.data)
        XCTAssertEqual(try reader.readString(), "Wai's MacBook Air")
        XCTAssertEqual(try reader.readData(), Data([0x01, 0x02, 0x03, 0xFF]))
        XCTAssertEqual(try reader.readString(), "")
    }

    func testUUIDRoundTrip() throws {
        let id = UUID()
        var writer = ByteWriter()
        writer.writeUUID(id)

        var reader = ByteReader(writer.data)
        XCTAssertEqual(try reader.readUUID(), id)
    }

    func testReadingPastEndThrows() {
        var reader = ByteReader(Data([0x01]))
        XCTAssertThrowsError(try reader.readUInt32())
    }
}
