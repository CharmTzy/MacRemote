import XCTest

final class PairedDeviceRecordTests: XCTestCase {
    func testDecodesRecordSavedBeforeWakeMetadataWasAdded() throws {
        let json = #"{"id":"1DB90F20-4A96-4CF5-A5AF-390B8E2419FA","name":"Mac","model":"Mac15,6","publicKey":"AQID","pairedAt":0}"#
        let record = try JSONDecoder().decode(PairedDeviceRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.name, "Mac")
        XCTAssertNil(record.lastKnownIPv4Address)
        XCTAssertNil(record.lastKnownBroadcastAddress)
        XCTAssertNil(record.wakeMACAddress)
    }

    func testDecodesRecordSavedBeforeInternetEndpointsWereAdded() throws {
        let json = #"{"id":"1DB90F20-4A96-4CF5-A5AF-390B8E2419FA","name":"Mac","model":"Mac15,6","publicKey":"AQID","pairedAt":0,"lastKnownIPv4Address":"192.168.1.20","wakeMACAddress":"a4:83:e7:aa:bb:cc"}"#
        let record = try JSONDecoder().decode(PairedDeviceRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.lastKnownIPv4Address, "192.168.1.20")
        XCTAssertEqual(record.wakeMACAddress, "a4:83:e7:aa:bb:cc")
        XCTAssertNil(record.lastKnownWANIPv4Address)
        XCTAssertTrue(record.knownIPv6Addresses.isEmpty)
    }

    func testInternetFieldsRoundTrip() throws {
        let record = PairedDeviceRecord(
            id: UUID(),
            name: "Mac",
            model: "Mac15,6",
            publicKey: Data([1, 2, 3]),
            pairedAt: Date(timeIntervalSince1970: 100),
            lastKnownIPv4Address: "192.168.1.20",
            wakeMACAddress: "a4:83:e7:aa:bb:cc",
            lastKnownWANIPv4Address: "203.0.113.7",
            lastKnownExternalPort: 53511,
            knownIPv6Addresses: ["2001:db8::1"]
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(PairedDeviceRecord.self, from: data)

        XCTAssertEqual(decoded, record)
    }

    func testConnectCandidatesOrderAndDefaults() {
        let record = PairedDeviceRecord(
            id: UUID(),
            name: "Mac",
            model: "Mac15,6",
            publicKey: Data(),
            pairedAt: Date(),
            lastKnownIPv4Address: "192.168.1.20",
            lastKnownWANIPv4Address: "203.0.113.7",
            lastKnownExternalPort: 40001,
            knownIPv6Addresses: ["fe80::bad", "2001:db8::1"]
        )

        let candidates = record.connectCandidates()
        XCTAssertEqual(candidates.map(\.kind), [.lanIPv4, .wanIPv6, .wanIPv4Mapped])
        XCTAssertEqual(candidates.last?.port, 40001)
    }
}
