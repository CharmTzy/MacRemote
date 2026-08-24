import XCTest

final class ConnectCandidateTests: XCTestCase {
    func testCandidatesOrderedLANThenIPv6ThenWAN() {
        let snapshot = ReachabilitySnapshot(
            lanIPv4Address: "192.168.1.20",
            wanIPv4Address: "203.0.113.7",
            externalPort: 53511,
            ipv6Addresses: ["2001:db8::1", "2a00:1450:4001:81b::200e"]
        )

        let candidates = ConnectCandidateBuilder.candidates(from: snapshot)

        XCTAssertEqual(candidates.map(\.kind), [.lanIPv4, .wanIPv6, .wanIPv6, .wanIPv4Mapped])
        XCTAssertEqual(candidates.first?.host, "192.168.1.20")
        XCTAssertEqual(candidates.last?.host, "203.0.113.7")
        XCTAssertEqual(candidates.last?.port, 53511)
    }

    func testMissingExternalPortFallsBackToDefault() {
        let snapshot = ReachabilitySnapshot(
            lanIPv4Address: nil,
            wanIPv4Address: "203.0.113.7",
            externalPort: nil,
            ipv6Addresses: []
        )

        let candidates = ConnectCandidateBuilder.candidates(from: snapshot)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].port, ServiceConstants.defaultControlPort)
    }

    func testVPNMeshCandidatesOrderedBetweenLANAndWAN() {
        let snapshot = ReachabilitySnapshot(
            lanIPv4Address: "192.168.1.20",
            wanIPv4Address: "203.0.113.7",
            externalPort: 40001,
            ipv6Addresses: ["2001:db8::1"],
            vpnIPv4Addresses: ["100.101.5.7", "192.168.1.9", "100.99.0.4"]
        )

        let candidates = ConnectCandidateBuilder.candidates(from: snapshot)

        XCTAssertEqual(candidates.map(\.kind), [.lanIPv4, .vpnMesh, .vpnMesh, .wanIPv6, .wanIPv4Mapped])
        // Non-mesh-range addresses (a plain private IP) are not VPNs.
        XCTAssertFalse(candidates.contains { $0.host == "192.168.1.9" })
    }

    func testPrivateRangeAndGarbageWANIPsRejected() {
        // A CG-NAT address is useless as a dial target and must not appear.
        let snapshot = ReachabilitySnapshot(
            lanIPv4Address: nil,
            wanIPv4Address: "100.64.12.9",
            externalPort: 12345,
            ipv6Addresses: []
        )
        XCTAssertTrue(ConnectCandidateBuilder.candidates(from: snapshot).isEmpty)

        XCTAssertTrue(ConnectCandidateBuilder.sanitizedIPv4("999.1.1.1") == nil)
        XCTAssertTrue(ConnectCandidateBuilder.sanitizedIPv4("192.168.0") == nil)
        XCTAssertTrue(ConnectCandidateBuilder.sanitizedIPv4("") == nil)
        XCTAssertTrue(ConnectCandidateBuilder.sanitizedIPv4("01.2.3.4") == nil)
        XCTAssertEqual(ConnectCandidateBuilder.sanitizedIPv4("203.0.113.7"), "203.0.113.7")
    }

    func testNonGlobalIPv6FilteredAndDeduped() {
        let result = ConnectCandidateBuilder.dedupedGlobalIPv6([
            "fe80::1",              // link-local
            "fd00::ab",             // unique-local
            "::1",                  // loopback
            "ff02::fb",             // multicast
            "not-an-address",
            "",
            "2001:db8::1",
            "2001:DB8::1"           // same address, different case
        ])
        XCTAssertEqual(result, ["2001:db8::1"])
    }
}
