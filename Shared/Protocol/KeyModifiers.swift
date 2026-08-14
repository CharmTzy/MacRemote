import Foundation

/// Which modifier keys are held for a `SpecialKey` event. The iPhone's
/// on-screen ⌘ ⌥ ⌃ ⇧ buttons arm these; a following key press consumes
/// them and they clear (the same "one tap, then act" pattern accessibility
/// sticky-keys uses), since there's no physical key being held down the
/// way there is on a real keyboard.
struct KeyModifiers: OptionSet, Sendable {
    let rawValue: UInt8

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let control = KeyModifiers(rawValue: 1 << 2)
    static let shift = KeyModifiers(rawValue: 1 << 3)
}
