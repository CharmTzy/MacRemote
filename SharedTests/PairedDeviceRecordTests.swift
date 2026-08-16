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
}
