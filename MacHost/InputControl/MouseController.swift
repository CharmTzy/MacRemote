import Foundation
import CoreGraphics

/// Posts synthetic mouse events via `CGEvent`. Coordinates are normalized
/// over the primary display — targeting a specific non-primary display
/// arrives with Phase 6's monitor picker.
///
/// Every call here silently does nothing if Accessibility isn't granted
/// (that's how `CGEvent.post` behaves — it doesn't error). The Permissions
/// tab is where that becomes visible to the user; this file doesn't
/// duplicate that status reporting.
enum MouseController {
    private static let eventSource = CGEventSource(stateID: .hidSystemState)

    static func move(to point: NormalizedPoint) {
        post(CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: pixelLocation(for: point), mouseButton: .left))
    }

    static func move(byX deltaX: Float, deltaY: Float) {
        guard let current = CGEvent(source: nil)?.location else { return }
        let destination = CGPoint(x: current.x + CGFloat(deltaX), y: current.y + CGFloat(deltaY))
        post(CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: destination, mouseButton: .left))
    }

    static func buttonDown(at point: NormalizedPoint, button: MouseButton) {
        let type: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        post(CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: pixelLocation(for: point), mouseButton: button.cgMouseButton))
    }

    static func buttonUp(at point: NormalizedPoint, button: MouseButton) {
        let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        post(CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: pixelLocation(for: point), mouseButton: button.cgMouseButton))
    }

    static func dragged(to point: NormalizedPoint, button: MouseButton) {
        let type: CGEventType = button == .left ? .leftMouseDragged : .rightMouseDragged
        post(CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: pixelLocation(for: point), mouseButton: button.cgMouseButton))
    }

    /// A complete click — down immediately followed by up, with the click
    /// count set so the system recognizes a fast double click as a double
    /// click rather than two singles.
    static func click(at point: NormalizedPoint, button: MouseButton, count: UInt8) {
        click(atPixelLocation: pixelLocation(for: point), button: button, count: count)
    }

    static func clickAtCurrentPosition(button: MouseButton, count: UInt8) {
        guard let location = CGEvent(source: nil)?.location else { return }
        click(atPixelLocation: location, button: button, count: count)
    }

    private static func click(atPixelLocation location: CGPoint, button: MouseButton, count: UInt8) {
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        let clampedCount = Int64(max(1, count))

        guard let down = CGEvent(mouseEventSource: eventSource, mouseType: downType, mouseCursorPosition: location, mouseButton: button.cgMouseButton),
              let up = CGEvent(mouseEventSource: eventSource, mouseType: upType, mouseCursorPosition: location, mouseButton: button.cgMouseButton) else {
            return
        }
        down.setIntegerValueField(.mouseEventClickState, value: clampedCount)
        up.setIntegerValueField(.mouseEventClickState, value: clampedCount)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func scroll(deltaX: Float, deltaY: Float) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private static func post(_ event: CGEvent?) {
        event?.post(tap: .cghidEventTap)
    }

    private static func pixelLocation(for point: NormalizedPoint) -> CGPoint {
        point.pixelPoint(in: CGDisplayBounds(CGMainDisplayID()))
    }
}

private extension MouseButton {
    var cgMouseButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        }
    }
}
