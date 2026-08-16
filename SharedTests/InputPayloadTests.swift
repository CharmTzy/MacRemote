import XCTest
import Foundation

final class InputPayloadTests: XCTestCase {
    func testNormalizedPointRoundTrip() throws {
        let point = NormalizedPoint(x: 0.6300001, y: 0.4199999)
        var writer = ByteWriter()
        point.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try NormalizedPoint.decode(from: &reader)
        XCTAssertEqual(decoded.x, point.x, accuracy: 0.0001)
        XCTAssertEqual(decoded.y, point.y, accuracy: 0.0001)
    }

    func testMouseMoveRoundTrip() throws {
        let payload = MouseMovePayload(position: NormalizedPoint(x: 0.1, y: 0.9))
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try MouseMovePayload.decode(from: &reader)
        XCTAssertEqual(decoded.position.x, payload.position.x, accuracy: 0.0001)
        XCTAssertEqual(decoded.position.y, payload.position.y, accuracy: 0.0001)
    }

    func testMouseButtonRoundTripDownAndUp() throws {
        for isDown in [true, false] {
            let payload = MouseButtonPayload(position: NormalizedPoint(x: 0.5, y: 0.5), button: .left, isDown: isDown)
            var writer = ByteWriter()
            payload.encode(into: &writer)
            var reader = ByteReader(writer.data)
            let decoded = try MouseButtonPayload.decode(from: &reader)
            XCTAssertEqual(decoded.button, payload.button)
            XCTAssertEqual(decoded.isDown, payload.isDown)
        }
    }

    func testMouseClickRoundTripForRightClick() throws {
        let payload = MouseClickPayload(position: NormalizedPoint(x: 0.25, y: 0.75), button: .right, clickCount: 1)
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try MouseClickPayload.decode(from: &reader)
        XCTAssertEqual(decoded.button, .right)
        XCTAssertEqual(decoded.clickCount, 1)
    }

    func testMouseDraggedRoundTrip() throws {
        let payload = MouseDraggedPayload(position: NormalizedPoint(x: 0.33, y: 0.66), button: .left)
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try MouseDraggedPayload.decode(from: &reader)
        XCTAssertEqual(decoded.button, .left)
    }

    func testScrollRoundTripWithNegativeDeltas() throws {
        let payload = ScrollPayload(deltaX: -12.5, deltaY: 40.25)
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try ScrollPayload.decode(from: &reader)
        XCTAssertEqual(decoded.deltaX, payload.deltaX, accuracy: 0.01)
        XCTAssertEqual(decoded.deltaY, payload.deltaY, accuracy: 0.01)
    }

    func testRelativeMouseMoveRoundTrip() throws {
        let payload = MouseMoveRelativePayload(deltaX: -14.5, deltaY: 8.25)
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try MouseMoveRelativePayload.decode(from: &reader)
        XCTAssertEqual(decoded, payload)
    }

    func testCurrentMouseClickRoundTrip() throws {
        let payload = MouseClickCurrentPayload(button: .right, clickCount: 2)
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        let decoded = try MouseClickCurrentPayload.decode(from: &reader)
        XCTAssertEqual(decoded, payload)
    }

    func testMouseMessagesRouteToInputCategory() {
        let messages: [ProtocolMessage] = [
            .mouseMove(MouseMovePayload(position: NormalizedPoint(x: 0, y: 0))),
            .mouseButton(MouseButtonPayload(position: NormalizedPoint(x: 0, y: 0), button: .left, isDown: true)),
            .mouseClick(MouseClickPayload(position: NormalizedPoint(x: 0, y: 0), button: .left, clickCount: 1)),
            .mouseDragged(MouseDraggedPayload(position: NormalizedPoint(x: 0, y: 0), button: .left)),
            .scroll(ScrollPayload(deltaX: 0, deltaY: 0)),
            .mouseMoveRelative(MouseMoveRelativePayload(deltaX: 0, deltaY: 0)),
            .mouseClickCurrent(MouseClickCurrentPayload(button: .left, clickCount: 1))
        ]
        for message in messages {
            XCTAssertEqual(message.category, .input)
        }
    }
}
