import XCTest

final class ReachabilityUpdatePayloadTests: XCTestCase {
    func testRoundTripWithAllFields() throws {
        let payload = ReachabilityUpdatePayload(
            lanIPv4Address: "192.168.1.20",
            wanIPv4Address: "203.0.113.7",
            externalPort: 53511,
            ipv6Addresses: ["2001:db8::1", "2607:f8b0:4006:81b::200e"],
            wakeMACAddress: "a4:83:e7:aa:bb:cc"
        )

        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try ReachabilityUpdatePayload.decode(from: &reader)

        XCTAssertEqual(decoded, payload)
    }

    func testEmptyOptionalsSurviveRoundTrip() throws {
        let payload = ReachabilityUpdatePayload()

        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try ReachabilityUpdatePayload.decode(from: &reader)

        XCTAssertNil(decoded.lanIPv4Address)
        XCTAssertNil(decoded.wanIPv4Address)
        XCTAssertNil(decoded.externalPort)
        XCTAssertTrue(decoded.ipv6Addresses.isEmpty)
    }

    func testDecodesAsSessionTypeThree() throws {
        // Wire-level check through the shared message dispatcher.
        let message = ProtocolMessage.reachabilityUpdate(ReachabilityUpdatePayload(wanIPv4Address: "203.0.113.7", externalPort: 40001))

        let decoded = try ProtocolMessage.decodeInner(message.encodedInner())
        guard case .reachabilityUpdate(let payload) = decoded else {
            return XCTFail("decoded as \(decoded)")
        }
        XCTAssertEqual(payload.wanIPv4Address, "203.0.113.7")
        XCTAssertEqual(payload.externalPort, 40001)
    }
}
