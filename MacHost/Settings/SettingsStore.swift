import Foundation

/// Centralizes `UserDefaults` keys for Mac-side preferences that non-View
/// code (`HostSessionManager`) needs to read, mirroring
/// `iPhoneRemote/Settings/SettingsStore.swift`.
enum SettingsStore {
    enum Key {
        static let clipboardSyncEnabled = "clipboardSyncEnabled"
    }

    static var clipboardSyncEnabled: Bool {
        // Defaults to on: `bool(forKey:)` returns false for a key that was
        // never set, so a missing value needs to read as true instead.
        UserDefaults.standard.object(forKey: Key.clipboardSyncEnabled) == nil
            || UserDefaults.standard.bool(forKey: Key.clipboardSyncEnabled)
    }
}
