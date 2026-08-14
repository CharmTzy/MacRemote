import Foundation

/// Centralizes the `UserDefaults` keys behind user preferences, so
/// `@AppStorage` in views and plain `UserDefaults` reads in view models
/// (`@AppStorage` is a SwiftUI `View`-only property wrapper) stay in sync
/// on the same key names instead of each spelling out a string literal.
enum SettingsStore {
    enum Key {
        static let streamingQuality = "streamingQuality"
        static let trackpadSensitivity = "trackpadSensitivity"
        static let naturalScrolling = "naturalScrolling"
    }

    static var streamingQuality: QualityProfile {
        guard let raw = UserDefaults.standard.string(forKey: Key.streamingQuality) else { return .auto }
        return QualityProfile(rawValue: raw) ?? .auto
    }
}
