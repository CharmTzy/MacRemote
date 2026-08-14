import Foundation
import AppKit

/// Polls `NSPasteboard.general.changeCount` for changes — there's no push
/// notification API for the system pasteboard, so polling is the standard
/// technique every Mac clipboard-sync tool uses. Tracks the change count
/// it produces itself so writing an incoming remote update doesn't loop
/// back around as if the user had copied it locally.
@MainActor
final class ClipboardMonitor {
    var onTextChanged: ((String) -> Void)?

    private var timer: Timer?
    private var lastChangeCount: Int
    private var suppressChangeCount: Int?

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let newTimer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Writes text from a remote peer to the local pasteboard, without
    /// treating the resulting change as something to broadcast back out.
    func applyRemoteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        suppressChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if suppressChangeCount == pasteboard.changeCount {
            suppressChangeCount = nil
            return
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        onTextChanged?(text)
    }
}
