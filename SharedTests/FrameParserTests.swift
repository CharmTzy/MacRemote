import XCTest
import Foundation

final class FrameParserTests: XCTestCase {
    func testSingleFrameInOneChunk() throws {
        var parser = FrameParser()
        let message = ProtocolMessage.ping(1234)
        let messages = try parser.feed(message.encodedFrame())

        XCTAssertEqual(messages.count, 1)
        guard case .ping(let value) = messages[0] else { return XCTFail("Expected .ping") }
        XCTAssertEqual(value, 1234)
    }

    func testMultipleFramesInOneChunk() throws {
        var parser = FrameParser()
        var combined = Data()
        combined.append(ProtocolMessage.ping(1).encodedFrame())
        combined.append(ProtocolMessage.pong(2).encodedFrame())
        combined.append(ProtocolMessage.ping(3).encodedFrame())

        let messages = try parser.feed(combined)
        XCTAssertEqual(messages.count, 3)
    }

    func testFrameSplitAcrossChunks() throws {
        var parser = FrameParser()
        let frame = ProtocolMessage.ping(999).encodedFrame()

        let midpoint = frame.count / 2
        let firstHalf = frame.prefix(midpoint)
        let secondHalf = frame.suffix(from: frame.startIndex + midpoint)

        let firstResult = try parser.feed(Data(firstHalf))
        XCTAssertTrue(firstResult.isEmpty)

        let secondResult = try parser.feed(Data(secondHalf))
        XCTAssertEqual(secondResult.count, 1)
        guard case .ping(let value) = secondResult[0] else { return XCTFail("Expected .ping") }
        XCTAssertEqual(value, 999)
    }

    func testOversizedFrameThrows() {
        var parser = FrameParser()
        var writer = ByteWriter()
        writer.writeUInt32(UInt32(FrameParser.maxFrameLength + 1))
        XCTAssertThrowsError(try parser.feed(writer.data))
    }
}
