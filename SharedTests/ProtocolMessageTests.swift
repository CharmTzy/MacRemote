import XCTest
import Foundation

final class ProtocolMessageTests: XCTestCase {
    func testHelloRoundTrip() throws {
        let payload = HelloPayload(
            protocolVersion: ProtocolVersion.current,
            deviceID: UUID(),
            deviceName: "Wai's MacBook Air",
            deviceModel: "Mac15,6",
            deviceKind: .mac,
            channelPurpose: .control
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

    func testHelloRoundTripForBothChannelPurposes() throws {
        for purpose: ChannelPurpose in [.control, .video] {
            let payload = HelloPayload(
                protocolVersion: ProtocolVersion.current,
                deviceID: UUID(),
                deviceName: "Wai's iPhone",
                deviceModel: "iPhone16,2",
                deviceKind: .iPhone,
                channelPurpose: purpose
            )
            var writer = ByteWriter()
            payload.encode(into: &writer)
            var reader = ByteReader(writer.data)
            XCTAssertEqual(try HelloPayload.decode(from: &reader), payload)
        }
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

    func testRunningApplicationsRoundTrip() throws {
        let payload = RunningApplicationsPayload(applications: [
            RunningApplicationDescriptor(
                bundleIdentifier: "com.apple.Safari",
                name: "Safari",
                iconPNGData: Data([1, 2, 3]),
                isActive: true
            )
        ])
        let frame = ProtocolMessage.runningApplications(payload).encodedFrame()
        var parser = FrameParser()
        let messages = try parser.feed(frame)
        guard case .runningApplications(let decoded)? = messages.first else {
            return XCTFail("Expected running applications")
        }
        XCTAssertEqual(decoded, payload)
    }

    func testActivateApplicationRoundTrip() throws {
        let frame = ProtocolMessage.activateApplication(
            ActivateApplicationPayload(bundleIdentifier: "com.apple.finder")
        ).encodedFrame()
        var parser = FrameParser()
        let messages = try parser.feed(frame)
        guard case .activateApplication(let decoded)? = messages.first else {
            return XCTFail("Expected activate application")
        }
        XCTAssertEqual(decoded.bundleIdentifier, "com.apple.finder")
    }
}
