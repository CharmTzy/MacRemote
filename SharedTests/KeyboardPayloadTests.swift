import XCTest
import Foundation

final class KeyboardPayloadTests: XCTestCase {
    func testTextInputRoundTripWithUnicode() throws {
        let payload = TextInputPayload(text: "Hello, 世界! 👋")
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try TextInputPayload.decode(from: &reader), payload)
    }

    func testSpecialKeyRoundTripPlainAndWithModifiers() throws {
        let plain = SpecialKeyPayload(key: .return, modifiers: [], isDown: true)
        var writer = ByteWriter()
        plain.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try SpecialKeyPayload.decode(from: &reader), plain)

        let shortcut = SpecialKeyPayload(key: .c, modifiers: [.command], isDown: false)
        writer = ByteWriter()
        shortcut.encode(into: &writer)
        reader = ByteReader(writer.data)
        XCTAssertEqual(try SpecialKeyPayload.decode(from: &reader), shortcut)
    }

    func testKeyModifiersCombineAsOptionSet() {
        let commandShift: KeyModifiers = [.command, .shift]
        XCTAssertTrue(commandShift.contains(.command))
        XCTAssertTrue(commandShift.contains(.shift))
        XCTAssertFalse(commandShift.contains(.option))
        XCTAssertFalse(commandShift.contains(.control))
    }

    func testKeyboardMessagesRouteToKeyboardCategory() {
        let messages: [ProtocolMessage] = [
            .textInput(TextInputPayload(text: "a")),
            .specialKey(SpecialKeyPayload(key: .escape, modifiers: [], isDown: true))
        ]
        for message in messages {
            XCTAssertEqual(message.category, .keyboard)
        }
    }
}
