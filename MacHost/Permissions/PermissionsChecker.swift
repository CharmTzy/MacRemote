import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

/// Reads and requests the two TCC permissions the host depends on. Screen
/// Recording is required to capture the display (Phase 3); Accessibility is
/// required to post synthetic input events (Phase 4/5). Neither is
/// meaningful until those phases exist, but the onboarding/status UI needs
/// real answers now rather than a placeholder.
enum PermissionsChecker {
    static func isScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system permission prompt if not already granted. Returns
    /// the current status; the OS does not report back the user's choice
    /// synchronously, so callers should re-check after the app regains focus.
    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the system Accessibility permission dialog if not already granted.
    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenRecordingSettings() {
        openSettingsPane(anchor: "Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        openSettingsPane(anchor: "Privacy_Accessibility")
    }

    private static func openSettingsPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
