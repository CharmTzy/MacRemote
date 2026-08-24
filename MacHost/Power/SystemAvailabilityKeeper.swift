import Foundation
import AppKit
import OSLog
import Combine

/// Keeps the Mac *available* even when nobody is sitting at it — this is
/// what lets an iPhone connect while the display is off, which used to fail:
/// with nothing holding a power assertion, macOS would idle-sleep the whole
/// system after the screen went dark, dropping Wi-Fi and the listening
/// socket with it.
///
/// Two things happen here:
///
/// 1. A `ProcessInfo` activity combining `.userInitiated` (defeats App Nap,
///    so our sockets and timers keep full service while unfocused/occluded)
///    and `.idleSystemSleepDisabled` (the system never idle-sleeps while the
///    host app is open). The *display* may still sleep on its own schedule —
///    that's exactly the desired state: screen off, Mac reachable.
///
/// 2. Sleep/wake observation, so the rest of the app can react: restart the
///    video pipeline when displays come back (ScreenCaptureKit streams die
///    on display sleep), refresh published network addresses after a wake,
///    and tell connected iPhones why their video paused.
///
/// Hardware limits that no software can override: closing a MacBook's lid on
/// battery always sleeps it, and a powered-off Mac has no network stack at
/// all. Lid-closed availability requires external power.
@MainActor
final class SystemAvailabilityKeeper: ObservableObject {
    @Published private(set) var displayIsAsleep = false
    @Published private(set) var systemIsAsleep = false

    /// Called when any display wakes or the system wakes from sleep.
    var onWake: (() -> Void)?
    /// Called when the displays go to sleep (system keeps running).
    var onDisplaySleep: (() -> Void)?

    private var activityToken: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []

    func begin() {
        guard activityToken == nil else { return }

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Mac Remote is available for incoming connections"
        )
        Logging.power.info("Holding power assertions: system stays awake while the app runs")

        let center = NSWorkspace.shared.notificationCenter
        for (name, handler) in [
            (NSWorkspace.screensDidSleepNotification, NotificationKind.displaySleep),
            (NSWorkspace.screensDidWakeNotification, NotificationKind.displayWake),
            (NSWorkspace.willSleepNotification, NotificationKind.systemSleep),
            (NSWorkspace.didWakeNotification, NotificationKind.systemWake)
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handle(handler) }
            })
        }
    }

    private enum NotificationKind { case displaySleep, displayWake, systemSleep, systemWake }

    private func handle(_ kind: NotificationKind) {
        switch kind {
        case .displaySleep:
            guard !displayIsAsleep else { return }
            displayIsAsleep = true
            Logging.power.notice("Displays asleep — staying reachable")
            onDisplaySleep?()
        case .displayWake:
            displayIsAsleep = false
            Logging.power.notice("Displays awake again")
            onWake?()
        case .systemSleep:
            systemIsAsleep = true
            Logging.power.notice("System going to sleep (explicit sleep or lid close)")
        case .systemWake:
            guard systemIsAsleep else { return }
            systemIsAsleep = false
            displayIsAsleep = false
            Logging.power.notice("System woke up")
            onWake?()
        }
    }

    deinit {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
