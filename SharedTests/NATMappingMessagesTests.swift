import XCTest

final class NATMappingMessagesTests: XCTestCase {
    // MARK: NAT-PMP

    func testNATPMPMapRequestLayout() {
        let data = NATMappingMessages.natpmpMapTCPRequest(internalPort: 53511, suggestedExternalPort: 53511, lifetimeSeconds: 7200)

        XCTAssertEqual([UInt8](data), [0, 2, 0, 0xD1, 0x07, 0xD1, 0x07, 0x00, 0x00, 0x1C, 0x20])
    }

    func testNATPMPPublicAddressResponseParsing() {
        var writer = ByteWriter()
        writer.writeUInt8(0)      // version
        writer.writeUInt8(0x80)   // response opcode 0
        writer.writeUInt16(0)     // result: success
        writer.writeUInt32(42)    // seconds since epoch
        writer.writeUInt32(0xCB00710F) // 203.0.113.15

        let parsed = NATMappingMessages.parseNATPMPResponse(writer.data, expectedOpcode: 0)
        XCTAssertEqual(parsed, .publicAddress(ipv4: "203.0.113.15"))
    }

    func testNATPMPMapResponseParsing() {
        var writer = ByteWriter()
        writer.writeUInt8(0)
        writer.writeUInt8(0x82)
        writer.writeUInt16(0)
        writer.writeUInt32(7)
        writer.writeUInt16(53511) // private port echo
        writer.writeUInt16(40001) // assigned external port
        writer.writeUInt32(3600)  // lifetime

        XCTAssertEqual(
            NATMappingMessages.parseNATPMPResponse(writer.data, expectedOpcode: 2),
            .map(externalPort: 40001, lifetimeSeconds: 3600)
        )
    }

    func testNATPMPRejectsErrorResultsAndZeroLifetime() {
        var error = ByteWriter()
        error.writeUInt8(0)
        error.writeUInt8(0x82)
        error.writeUInt16(4) // NOT_AUTHORIZED
        error.writeUInt32(0)
        error.writeUInt16(1)
        error.writeUInt16(1)
        error.writeUInt32(60)
        XCTAssertNil(NATMappingMessages.parseNATPMPResponse(error.data, expectedOpcode: 2))

        var zeroLifetime = ByteWriter()
        zeroLifetime.writeUInt8(0)
        zeroLifetime.writeUInt8(0x82)
        zeroLifetime.writeUInt16(0)
        zeroLifetime.writeUInt32(0)
        zeroLifetime.writeUInt16(1)
        zeroLifetime.writeUInt16(1)
        zeroLifetime.writeUInt32(0)
        XCTAssertNil(NATMappingMessages.parseNATPMPResponse(zeroLifetime.data, expectedOpcode: 2))
    }

    // MARK: PCP (RFC 6887 layouts)

    private let nonce = Data([
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
        0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C
    ])

    private func buildPCPMapRequest() -> Data? {
        NATMappingMessages.pcpMapTCPRequest(
            clientIPv4: "192.168.1.20",
            nonce: nonce,
            internalPort: 53511,
            suggestedExternalPort: 53511,
            lifetimeSeconds: 7200
        )
    }

    func testPCPMapRequestLayout() throws {
        let request = try XCTUnwrap(buildPCPMapRequest())

        XCTAssertEqual(request.count, 24 + 36) // base header + MAP payload
        XCTAssertEqual(Array(request.prefix(4)), [2, 1, 0, 0])
        // Client IP field sits at bytes 8–23 as an IPv4-mapped address:
        // 10 zero bytes, then ::ffff marker, then the octets.
        XCTAssertEqual(request[18], 0xFF)
        XCTAssertEqual(request[19], 0xFF)
        XCTAssertEqual(request[20], 192)
        XCTAssertEqual(request[21], 168)
        XCTAssertEqual(request[22], 1)
        XCTAssertEqual(request[23], 20)
        XCTAssertEqual(request[24..<36], nonce)
        XCTAssertEqual(request[36], 6) // TCP
    }

    func testPCPMapRequestRequiresTwelveByteNonce() {
        XCTAssertNil(NATMappingMessages.pcpMapTCPRequest(
            clientIPv4: nil, nonce: Data(repeating: 0, count: 11),
            internalPort: 1, suggestedExternalPort: 1, lifetimeSeconds: 60
        ))
    }

    func testPCPSuccessResponseRoundTrip() throws {
        // The assigned external address as an IPv4-mapped address for 203.0.113.99.
        var addressWriter = ByteWriter()
        addressWriter.writeRawData(Data(repeating: 0, count: 10))
        addressWriter.writeRawData(Data([0xFF, 0xFF]))
        addressWriter.writeRawData(Data([203, 0, 113, 99]))
        let mappedExternal = addressWriter.data

        var writer = ByteWriter()
        writer.writeUInt8(2)      // version
        writer.writeUInt8(0x81)   // response opcode MAP
        writer.writeUInt8(0)      // reserved
        writer.writeUInt8(0)      // result: SUCCESS
        writer.writeUInt32(1800)  // assigned lifetime
        writer.writeUInt32(99)    // epoch
        writer.writeRawData(Data(repeating: 0, count: 12)) // reserved 96 bits
        writer.writeRawData(nonce)
        writer.writeUInt8(6)      // protocol TCP
        writer.writeUInt8(0); writer.writeUInt8(0); writer.writeUInt8(0) // reserved ×3
        writer.writeUInt16(53511) // internal port
        writer.writeUInt16(55555) // assigned external port
        writer.writeRawData(mappedExternal)

        let parsed = try XCTUnwrap(NATMappingMessages.parsePCPMapResponse(writer.data, nonce: nonce))
        XCTAssertEqual(parsed.lifetimeSeconds, 1800)
        XCTAssertEqual(parsed.externalPort, 55555)
        XCTAssertEqual(parsed.externalIPv4, "203.0.113.99")
    }

    func testPCPUnspecifiedExternalAddressYieldsNil() throws {
        var writer = ByteWriter()
        writer.writeUInt8(2); writer.writeUInt8(0x81); writer.writeUInt8(0); writer.writeUInt8(0)
        writer.writeUInt32(1800)
        writer.writeUInt32(99)
        writer.writeRawData(Data(repeating: 0, count: 12))
        writer.writeRawData(nonce)
        writer.writeUInt8(6); writer.writeUInt8(0); writer.writeUInt8(0); writer.writeUInt8(0)
        writer.writeUInt16(53511)
        writer.writeUInt16(55555)
        writer.writeRawData(Data(repeating: 0, count: 16)) // unspecified (::)

        let parsed = try XCTUnwrap(NATMappingMessages.parsePCPMapResponse(writer.data, nonce: nonce))
        XCTAssertNil(parsed.externalIPv4)
    }

    func testPCPErrorResponseIsRejected() {
        var writer = ByteWriter()
        writer.writeUInt8(2)
        writer.writeUInt8(0x81)
        writer.writeUInt8(0)
        writer.writeUInt8(2) // NOT_AUTHORIZED
        writer.writeUInt32(30)
        writer.writeUInt32(0)
        writer.writeRawData(Data(repeating: 0, count: 24))

        XCTAssertNil(NATMappingMessages.parsePCPMapResponse(writer.data, nonce: nonce))
    }

    // MARK: CG-NAT detection

    func testLooksPrivate() {
        XCTAssertTrue(ConnectCandidateBuilder.isPrivateIPv4("100.64.0.1"))   // CG-NAT
        XCTAssertTrue(ConnectCandidateBuilder.isPrivateIPv4("10.1.2.3"))
        XCTAssertTrue(ConnectCandidateBuilder.isPrivateIPv4("172.16.0.9"))
        XCTAssertTrue(ConnectCandidateBuilder.isPrivateIPv4("192.168.1.1"))
        XCTAssertTrue(ConnectCandidateBuilder.isPrivateIPv4("169.254.3.3"))
        XCTAssertFalse(ConnectCandidateBuilder.isPrivateIPv4("203.0.113.7"))
        XCTAssertFalse(ConnectCandidateBuilder.isPrivateIPv4("100.200.1.1"))
        XCTAssertTrue(ConnectCandidateBuilder.isPrivateIPv4("garbage"))
    }
}
