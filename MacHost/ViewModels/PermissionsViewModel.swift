import Foundation

@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var accessibilityGranted = false

    var allPermissionsGranted: Bool { screenRecordingGranted && accessibilityGranted }

    func refresh() {
        screenRecordingGranted = PermissionsChecker.isScreenRecordingGranted()
        accessibilityGranted = PermissionsChecker.isAccessibilityGranted()
    }

    func requestScreenRecording() {
        PermissionsChecker.requestScreenRecordingAccess()
        refresh()
    }

    func requestAccessibility() {
        PermissionsChecker.requestAccessibilityAccess()
        refresh()
    }

    func openScreenRecordingSettings() {
        PermissionsChecker.openScreenRecordingSettings()
    }

    func openAccessibilitySettings() {
        PermissionsChecker.openAccessibilitySettings()
    }
}
