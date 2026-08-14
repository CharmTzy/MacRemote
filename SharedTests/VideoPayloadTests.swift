import XCTest
import Foundation
import CryptoKit

final class VideoPayloadTests: XCTestCase {
    func testVideoConfigRoundTrip() throws {
        let payload = VideoConfigPayload(width: 1920, height: 1080, sps: Data([0x67, 0x42, 0x00]), pps: Data([0x68, 0xCE]))
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try VideoConfigPayload.decode(from: &reader), payload)
    }

    func testVideoFrameRoundTripKeyAndDelta() throws {
        for payload in [
            VideoFramePayload(isKeyFrame: true, sampleData: Data((0..<256).map { UInt8($0 % 256) })),
            VideoFramePayload(isKeyFrame: false, sampleData: Data([0x00, 0x00, 0x00, 0x04, 0x41]))
        ] {
            var writer = ByteWriter()
            payload.encode(into: &writer)
            var reader = ByteReader(writer.data)
            XCTAssertEqual(try VideoFramePayload.decode(from: &reader), payload)
        }
    }

    func testVideoErrorRoundTrip() throws {
        let payload = VideoErrorPayload(reason: "Screen Recording permission is required.")
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try VideoErrorPayload.decode(from: &reader), payload)
    }

    func testVideoFrameSurvivesSecureEnvelopeRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = SecureSession(key: key)
        var receiver = SecureSession(key: key)

        let inner = ProtocolMessage.videoFrame(VideoFramePayload(isKeyFrame: true, sampleData: Data(repeating: 0xAB, count: 128)))
        let sealed = try sender.seal(inner.encodedInner())
        let opened = try receiver.open(counter: sealed.counter, combined: sealed.combined)
        let decoded = try ProtocolMessage.decodeInner(opened)

        guard case .videoFrame(let payload) = decoded else {
            return XCTFail("Expected .videoFrame")
        }
        XCTAssertTrue(payload.isKeyFrame)
        XCTAssertEqual(payload.sampleData, Data(repeating: 0xAB, count: 128))
    }
}
