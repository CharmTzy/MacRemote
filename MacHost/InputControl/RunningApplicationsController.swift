import AppKit

enum RunningApplicationsController {
    private static let maximumApplications = 12
    private static let iconSize = NSSize(width: 64, height: 64)

    static func snapshot() -> RunningApplicationsPayload {
        var seenBundleIdentifiers = Set<String>()
        let applications = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .filter { application in
                guard let bundleIdentifier = application.bundleIdentifier,
                      bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
                return seenBundleIdentifiers.insert(bundleIdentifier).inserted
            }
            .sorted { lhs, rhs in
                return (lhs.localizedName ?? "").localizedCaseInsensitiveCompare(rhs.localizedName ?? "") == .orderedAscending
            }
            .prefix(maximumApplications)
            .compactMap { application -> RunningApplicationDescriptor? in
                guard let bundleIdentifier = application.bundleIdentifier,
                      let name = application.localizedName else { return nil }
                return RunningApplicationDescriptor(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    iconPNGData: pngData(for: application.icon),
                    isActive: application.isActive
                )
            }
        return RunningApplicationsPayload(applications: Array(applications))
    }

    static func activate(bundleIdentifier: String, completion: @escaping (Bool) -> Void) {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier && $0.activationPolicy == .regular && !$0.isTerminated
        }), let bundleURL = application.bundleURL else {
            completion(false)
            return
        }

        // `NSRunningApplication.activate` can return false when this host is
        // no longer frontmost. Re-open the already-running app through
        // NSWorkspace instead; `activates` reliably brings all of its windows
        // forward from a background menu/window app.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { openedApplication, error in
            DispatchQueue.main.async {
                completion(openedApplication != nil && error == nil)
            }
        }
    }

    private static func pngData(for source: NSImage?) -> Data {
        guard let source else { return Data() }
        let rendered = NSImage(size: iconSize)
        rendered.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: iconSize))
        rendered.unlockFocus()

        guard let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [.compressionFactor: 0.8]) else {
            return Data()
        }
        return png
    }
}
