import Foundation
import ScreenCaptureKit
import CoreGraphics

/// Lists capturable displays via ScreenCaptureKit. Calling this triggers
/// the Screen Recording permission prompt the first time, if it hasn't
/// been granted yet — check `PermissionsChecker.isScreenRecordingGranted()`
/// first if the caller wants to avoid surprising the user with it.
enum DisplayCatalog {
    struct DisplayInfo: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let width: Int
        let height: Int
        let isMain: Bool
    }

    static func availableDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.current
        let mainDisplayID = CGMainDisplayID()
        return content.displays.map { display in
            DisplayInfo(id: display.displayID, width: display.width, height: display.height, isMain: display.displayID == mainDisplayID)
        }
    }

    /// The `SCDisplay` matching a previously-listed `DisplayInfo.id`, since
    /// `SCStream` needs the live ScreenCaptureKit object, not just the ID.
    static func scDisplay(for id: CGDirectDisplayID) async throws -> SCDisplay? {
        let content = try await SCShareableContent.current
        return content.displays.first { $0.displayID == id }
    }

    static func primaryDisplay() async throws -> SCDisplay? {
        let content = try await SCShareableContent.current
        let mainDisplayID = CGMainDisplayID()
        return content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first
    }
}
