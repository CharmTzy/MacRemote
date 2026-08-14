import XCTest
import Foundation

final class ClipboardPayloadTests: XCTestCase {
    func testClipboardRoundTripWithURL() throws {
        let payload = ClipboardPayload(text: "https://example.com/path?query=1")
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try ClipboardPayload.decode(from: &reader), payload)
    }

    func testClipboardRoutesToClipboardCategory() {
        XCTAssertEqual(ProtocolMessage.clipboardUpdate(ClipboardPayload(text: "hi")).category, .clipboard)
    }
}
