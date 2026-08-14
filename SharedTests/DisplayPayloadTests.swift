import XCTest
import Foundation

final class DisplayPayloadTests: XCTestCase {
    func testDisplayDescriptorRoundTrip() throws {
        let descriptor = DisplayDescriptor(id: 69732865, width: 1920, height: 1080, isMain: true, name: "Main Display")
        var writer = ByteWriter()
        descriptor.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try DisplayDescriptor.decode(from: &reader), descriptor)
    }

    func testDisplayListRoundTripWithMultipleDisplays() throws {
        let payload = DisplayListPayload(displays: [
            DisplayDescriptor(id: 1, width: 1920, height: 1080, isMain: true, name: "Main Display"),
            DisplayDescriptor(id: 2, width: 3840, height: 2160, isMain: false, name: "Display 2")
        ])
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try DisplayListPayload.decode(from: &reader), payload)
    }

    func testDisplayListRoundTripEmpty() throws {
        let payload = DisplayListPayload(displays: [])
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try DisplayListPayload.decode(from: &reader), payload)
    }

    func testSelectDisplayRoundTrip() throws {
        let payload = SelectDisplayPayload(displayID: 123456)
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try SelectDisplayPayload.decode(from: &reader), payload)
    }
}
