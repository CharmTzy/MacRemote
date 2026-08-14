import Foundation
import AppKit
import OSLog

/// Executes `SystemCommand`s. Three different mechanisms, chosen per
/// command for the most reliable available technique:
///
/// - Commands with an ordinary default keyboard shortcut (Spotlight,
///   App Switcher, Mission Control, Launchpad, Show Desktop, Lock Screen)
///   reuse `KeyboardController`, the same mechanism Phase 5 already built.
///   This relies on the user not having changed those shortcuts in System
///   Settings — the one real limitation of this approach.
/// - Sleep/Restart/Shut Down/Mute/Volume go through AppleScript
///   (`NSAppleScript` talking to System Events), since macOS has no public
///   `CGEvent`-level API for them. This requires the Automation permission
///   (Mac prompts on first use) and `NSAppleEventsUsageDescription` in
///   Info.plist — see SECURITY.md.
/// - Play/Pause and track navigation use the "media key" `NSEvent`
///   technique (`NX_KEYTYPE_*` system-defined events) — there's no public
///   API for these either, and this one has no AppleScript equivalent
///   that works across whatever app currently owns Now Playing. This is
///   the least-documented, highest-risk mechanism in this file.
enum SystemCommandController {
    static func perform(_ command: SystemCommand) {
        switch command {
        case .missionControl:
            KeyboardController.sendChord(.upArrow, modifiers: [.control])
        case .launchpad:
            KeyboardController.sendChord(.f4, modifiers: [])
        case .spotlight:
            KeyboardController.sendChord(.space, modifiers: [.command])
        case .appSwitcher:
            KeyboardController.sendChord(.tab, modifiers: [.command])
        case .showDesktop:
            KeyboardController.sendChord(.f11, modifiers: [])
        case .lockScreen:
            KeyboardController.sendChord(.q, modifiers: [.command, .control])
        case .sleep:
            runAppleScript(#"tell application "System Events" to sleep"#)
        case .restart:
            runAppleScript(#"tell application "System Events" to restart"#)
        case .shutdown:
            runAppleScript(#"tell application "System Events" to shut down"#)
        case .mute:
            runAppleScript(#"tell application "System Events" to set volume output muted (not (output muted of (get volume settings)))"#)
        case .volumeUp:
            runAppleScript(#"tell application "System Events" to set volume output volume ((output volume of (get volume settings)) + 10)"#)
        case .volumeDown:
            runAppleScript(#"tell application "System Events" to set volume output volume ((output volume of (get volume settings)) - 10)"#)
        case .playPause:
            postMediaKey(.play)
        case .previousTrack:
            postMediaKey(.previous)
        case .nextTrack:
            postMediaKey(.next)
        }
    }

    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            Logging.session.error("AppleScript command failed: \(error, privacy: .public)")
        }
    }

    private enum MediaKey: Int32 {
        case play = 16
        case next = 17
        case previous = 18
    }

    private static func postMediaKey(_ key: MediaKey) {
        postMediaKeyEvent(key, isDown: true)
        postMediaKeyEvent(key, isDown: false)
    }

    private static func postMediaKeyEvent(_ key: MediaKey, isDown: Bool) {
        let keyState: Int32 = isDown ? 0xA : 0xB
        let data1 = Int((key.rawValue << 16) | (keyState << 8))

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: isDown ? 0xA00 : 0xB00),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ), let cgEvent = event.cgEvent else {
            return
        }
        cgEvent.post(tap: .cghidEventTap)
    }
}
