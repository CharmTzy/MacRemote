import Foundation

/// Keys that need an actual key-code-level `CGEvent`, as opposed to plain
/// typed text (which travels as `TextInputPayload` and is injected as
/// literal Unicode, independent of keyboard layout). Covers navigation/
/// editing keys, function keys, and the letters/digits needed for
/// shortcuts like Cmd+C — deliberately not literal macOS virtual key
/// codes, so the wire protocol doesn't depend on Mac-specific numbering;
/// `MacHost/InputControl/VirtualKeyCode.swift` owns that mapping.
enum SpecialKey: UInt8, Sendable {
    case delete = 1
    case forwardDelete = 2
    case `return` = 3
    case tab = 4
    case escape = 5
    case leftArrow = 6
    case rightArrow = 7
    case upArrow = 8
    case downArrow = 9
    case space = 10
    case home = 11
    case end = 12
    case pageUp = 13
    case pageDown = 14

    case f1 = 20, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    case a = 40, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z

    case digit0 = 70, digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9
}
