import Foundation
import CoreGraphics

/// Posts synthetic keyboard events via `CGEvent`. Plain text goes through
/// Unicode string injection (works regardless of keyboard layout, script,
/// or autocorrect); everything that needs a real key code — navigation,
/// function keys, shortcuts — goes through `VirtualKeyCode`.
enum KeyboardController {
    private static let eventSource = CGEventSource(stateID: .hidSystemState)

    /// Injects literal text. Not usable for shortcuts — a Unicode-string
    /// keyboard event types characters, it doesn't invoke menu commands
    /// the way an actual Cmd+C key event does. Use `sendSpecialKey` for that.
    static func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)

        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else { return }
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cghidEventTap)

        guard let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else { return }
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.post(tap: .cghidEventTap)
    }

    static func sendSpecialKey(_ key: SpecialKey, modifiers: KeyModifiers, isDown: Bool) {
        guard let virtualKey = VirtualKeyCode.code(for: key),
              let event = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: isDown) else {
            return
        }
        event.flags = modifiers.cgEventFlags
        event.post(tap: .cghidEventTap)
    }

    /// A complete press-and-release — used for system shortcuts
    /// (`SystemCommandController`) that don't need down/up as separate
    /// steps the way a held key during typing does.
    static func sendChord(_ key: SpecialKey, modifiers: KeyModifiers) {
        sendSpecialKey(key, modifiers: modifiers, isDown: true)
        sendSpecialKey(key, modifiers: modifiers, isDown: false)
    }
}

private extension KeyModifiers {
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}
