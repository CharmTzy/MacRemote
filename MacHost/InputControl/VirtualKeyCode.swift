import Foundation
import CoreGraphics

/// Maps the wire protocol's platform-neutral `SpecialKey` to the macOS
/// virtual key codes `CGEvent` needs. These are the standard ANSI-layout
/// `kVK_*` constants from `<HIToolbox/Events.h>`, hardcoded rather than
/// pulled in via `import Carbon` — the whole table is 50-odd well-known,
/// stable values, and that's a smaller footprint than linking Carbon for it.
enum VirtualKeyCode {
    static func code(for key: SpecialKey) -> CGKeyCode? {
        switch key {
        case .delete: return 0x33
        case .forwardDelete: return 0x75
        case .return: return 0x24
        case .tab: return 0x30
        case .escape: return 0x35
        case .leftArrow: return 0x7B
        case .rightArrow: return 0x7C
        case .downArrow: return 0x7D
        case .upArrow: return 0x7E
        case .space: return 0x31
        case .home: return 0x73
        case .end: return 0x77
        case .pageUp: return 0x74
        case .pageDown: return 0x79

        case .f1: return 0x7A
        case .f2: return 0x78
        case .f3: return 0x63
        case .f4: return 0x76
        case .f5: return 0x60
        case .f6: return 0x61
        case .f7: return 0x62
        case .f8: return 0x64
        case .f9: return 0x65
        case .f10: return 0x6D
        case .f11: return 0x67
        case .f12: return 0x6F

        case .a: return 0x00
        case .b: return 0x0B
        case .c: return 0x08
        case .d: return 0x02
        case .e: return 0x0E
        case .f: return 0x03
        case .g: return 0x05
        case .h: return 0x04
        case .i: return 0x22
        case .j: return 0x26
        case .k: return 0x28
        case .l: return 0x25
        case .m: return 0x2E
        case .n: return 0x2D
        case .o: return 0x1F
        case .p: return 0x23
        case .q: return 0x0C
        case .r: return 0x0F
        case .s: return 0x01
        case .t: return 0x11
        case .u: return 0x20
        case .v: return 0x09
        case .w: return 0x0D
        case .x: return 0x07
        case .y: return 0x10
        case .z: return 0x06

        case .digit0: return 0x1D
        case .digit1: return 0x12
        case .digit2: return 0x13
        case .digit3: return 0x14
        case .digit4: return 0x15
        case .digit5: return 0x17
        case .digit6: return 0x16
        case .digit7: return 0x1A
        case .digit8: return 0x1C
        case .digit9: return 0x19
        }
    }
}
