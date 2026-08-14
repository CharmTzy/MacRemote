import Foundation

/// A one-shot Mac action that isn't really "input" in the mouse/keyboard
/// sense — shown as a Shortcuts list on the iPhone. `restart` and
/// `shutdown` require the iPhone to confirm before sending; the Mac
/// performs whatever it's told without a second confirmation of its own,
/// since the whole point is remote control.
enum SystemCommand: UInt8, Sendable, CaseIterable {
    case missionControl = 1
    case launchpad = 2
    case spotlight = 3
    case appSwitcher = 4
    case showDesktop = 5
    case lockScreen = 6
    case sleep = 7
    case mute = 8
    case volumeUp = 9
    case volumeDown = 10
    case playPause = 11
    case previousTrack = 12
    case nextTrack = 13
    case restart = 14
    case shutdown = 15

    var label: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .launchpad: return "Launchpad"
        case .spotlight: return "Spotlight"
        case .appSwitcher: return "App Switcher"
        case .showDesktop: return "Show Desktop"
        case .lockScreen: return "Lock Mac"
        case .sleep: return "Sleep Mac"
        case .mute: return "Mute"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .playPause: return "Play/Pause"
        case .previousTrack: return "Previous Track"
        case .nextTrack: return "Next Track"
        case .restart: return "Restart Mac"
        case .shutdown: return "Shut Down Mac"
        }
    }

    var systemImage: String {
        switch self {
        case .missionControl: return "rectangle.on.rectangle.angled"
        case .launchpad: return "square.grid.3x3"
        case .spotlight: return "magnifyingglass"
        case .appSwitcher: return "square.stack"
        case .showDesktop: return "desktopcomputer"
        case .lockScreen: return "lock"
        case .sleep: return "moon"
        case .mute: return "speaker.slash"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .playPause: return "playpause"
        case .previousTrack: return "backward.end"
        case .nextTrack: return "forward.end"
        case .restart: return "arrow.clockwise"
        case .shutdown: return "power"
        }
    }

    /// Sent from the iPhone before actually sending the command — the
    /// remote viewer shows a confirmation dialog for these rather than
    /// firing on a single tap.
    var requiresConfirmation: Bool {
        self == .restart || self == .shutdown
    }
}
