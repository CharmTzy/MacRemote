import Foundation
import Combine

/// Owns the modifier-arm state and the text-diffing logic that turns
/// system-keyboard input into protocol messages. Framework-agnostic (no
/// SwiftUI/UIKit) so that logic is easy to reason about on its own;
/// `KeyboardInputView` is the thin SwiftUI layer on top.
///
/// The diffing exists because the system keyboard hands SwiftUI a
/// `TextField`'s full string on every keystroke, not individual key
/// events — this reconstructs "what changed" (an insertion, a backspace,
/// or — for autocorrect swaps and similar — a full resync) and turns that
/// into the right wire messages.
@MainActor
final class KeyboardInputSession: ObservableObject {
    @Published private(set) var activeModifiers: KeyModifiers = []
    @Published var fieldText: String = "" {
        didSet { processChange(from: oldValue, to: fieldText) }
    }

    var send: ((ProtocolMessage) -> Void)?

    func toggleModifier(_ modifier: KeyModifiers) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
        }
    }

    /// Sends a complete press-and-release, consuming (and clearing) any
    /// armed modifiers — matches how the on-screen ⌘/⌥/⌃/⇧ buttons behave:
    /// tap to arm, next key press uses it, then it's disarmed.
    func sendSpecialKey(_ key: SpecialKey) {
        let modifiers = activeModifiers
        send?(.specialKey(SpecialKeyPayload(key: key, modifiers: modifiers, isDown: true)))
        send?(.specialKey(SpecialKeyPayload(key: key, modifiers: modifiers, isDown: false)))
        activeModifiers = []
    }

    private func processChange(from oldValue: String, to newValue: String) {
        guard oldValue != newValue else { return }

        if newValue.count > oldValue.count, newValue.hasPrefix(oldValue) {
            handleInsertion(String(newValue.dropFirst(oldValue.count)))
        } else if newValue.count < oldValue.count, oldValue.hasPrefix(newValue) {
            for _ in 0..<(oldValue.count - newValue.count) {
                sendDeleteKey()
            }
        } else {
            // A non-trivial edit — autocorrect swapped a word, the cursor
            // moved and text was inserted elsewhere, etc. Resync by
            // clearing everything typed so far and retyping the new text.
            for _ in 0..<oldValue.count {
                sendDeleteKey()
            }
            if !newValue.isEmpty {
                handleInsertion(newValue)
            }
        }
    }

    private func handleInsertion(_ text: String) {
        if text == "\n" {
            sendSpecialKey(.return)
            return
        }

        if !activeModifiers.isEmpty, text.count == 1, let character = text.lowercased().first,
           let key = Self.specialKey(forCharacter: character) {
            sendSpecialKey(key)
            return
        }

        send?(.textInput(TextInputPayload(text: text)))
    }

    private func sendDeleteKey() {
        send?(.specialKey(SpecialKeyPayload(key: .delete, modifiers: [], isDown: true)))
        send?(.specialKey(SpecialKeyPayload(key: .delete, modifiers: [], isDown: false)))
    }

    private static func specialKey(forCharacter character: Character) -> SpecialKey? {
        switch character {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "0": return .digit0
        case "1": return .digit1
        case "2": return .digit2
        case "3": return .digit3
        case "4": return .digit4
        case "5": return .digit5
        case "6": return .digit6
        case "7": return .digit7
        case "8": return .digit8
        case "9": return .digit9
        default: return nil
        }
    }
}
