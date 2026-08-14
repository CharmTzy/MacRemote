import Foundation

/// State machine for a single Mac connection, as seen from the iPhone.
/// Drives both the status text/color in the device list and what the UI
/// allows the user to do next.
enum ConnectionState: Equatable, Hashable, Sendable {
    case searching
    case available
    case connecting
    case connected
    case offline
    case authenticationFailed
    case reconnecting

    var label: String {
        switch self {
        case .searching: return "Searching…"
        case .available: return "Tap to Connect"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .offline: return "Offline"
        case .authenticationFailed: return "Authentication Failed"
        case .reconnecting: return "Reconnecting…"
        }
    }
}
