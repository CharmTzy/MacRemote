import XCTest
import Foundation

final class ProtocolMessageTests: XCTestCase {
    func testHelloRoundTrip() throws {
        let payload = HelloPayload(
            protocolVersion: ProtocolVersion.current,
            deviceID: UUID(),
            deviceName: "Wai's MacBook Air",
            deviceModel: "Mac15,6",
            deviceKind: .mac
        )
        let message = ProtocolMessage.hello(payload)
        let frame = message.encodedFrame()

        // Strip the 4-byte length prefix the way FrameParser would, then decode directly.
        var reader = ByteReader(frame)
        _ = try reader.readUInt32()
        let category = try reader.readUInt8()
        let type = try reader.readUInt8()
        let remaining = frame.suffix(from: frame.startIndex + 6)

        let decoded = try ProtocolMessage.decode(
            category: MessageCategory(rawValue: category)!,
            type: type,
            payload: Data(remaining)
        )

        guard case .hello(let decodedPayload) = decoded else {
            return XCTFail("Expected .hello")
        }
        XCTAssertEqual(decodedPayload, payload)
    }

    func testHelloAckRejectionCarriesReason() throws {
        let payload = HelloAckPayload(
            protocolVersion: ProtocolVersion.current,
            deviceID: UUID(),
            deviceName: "Wai's MacBook Air",
            deviceModel: "Mac15,6",
            accepted: false,
            reason: "This device is not paired."
        )
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try HelloAckPayload.decode(from: &reader)
        XCTAssertEqual(decoded, payload)
    }
}
