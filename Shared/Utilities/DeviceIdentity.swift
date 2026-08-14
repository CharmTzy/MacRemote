import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// This device's stable identity for the Hello handshake: a UUID generated
/// once and kept in the Keychain (survives app reinstalls, unlike
/// `UserDefaults`), plus a human-readable name and model string.
///
/// This is *not* the cryptographic identity used for pairing/authentication
/// — that lands in Phase 2 and will live alongside this under its own
/// Keychain service.
enum DeviceIdentity {
    private static let keychain = KeychainStore(service: "com.macremote.identity")
    private static let deviceIDAccount = "local-device-id"

    static func localDeviceID() -> UUID {
        if let existing = try? keychain.get(account: deviceIDAccount),
           let string = String(data: existing, encoding: .utf8),
           let uuid = UUID(uuidString: string) {
            return uuid
        }
        let newID = UUID()
        try? keychain.set(Data(newID.uuidString.utf8), account: deviceIDAccount)
        return newID
    }

    static var localDeviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    static var localDeviceModel: String {
        #if os(macOS)
        return MacModelInfo.modelIdentifier()
        #else
        return UIDevice.current.model
        #endif
    }

    static var localDeviceKind: DeviceKind {
        #if os(macOS)
        return .mac
        #else
        return .iPhone
        #endif
    }
}
