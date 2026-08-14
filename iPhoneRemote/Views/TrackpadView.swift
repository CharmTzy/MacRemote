import SwiftUI
import UIKit

/// Relative-movement trackpad, as an alternative to touching the mirrored
/// screen directly. Tracks its own "virtual cursor" position locally
/// (starting at center) rather than reading the Mac's real cursor
/// position back — there's no protocol message for that yet, so if the
/// physical Mac trackpad moves the cursor at the same time, this can drift
/// out of sync until the next direct-touch tap resets a known position.
///
/// Scope note: this mode moves the cursor and clicks, but doesn't drag —
/// distinguishing "move" from "click-and-drag" from touch alone needs a
/// hold-then-pan gesture this phase didn't build. Use Direct Touch (the
/// mirrored screen itself) for dragging.
struct TrackpadView: View {
    @ObservedObject var controlSession: DeviceSessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var virtualCursor = NormalizedPoint(x: 0.5, y: 0.5)
    @State private var hasInteracted = false
    @AppStorage(SettingsStore.Key.trackpadSensitivity) private var sensitivity: Double = 1.0
    @AppStorage(SettingsStore.Key.naturalScrolling) private var naturalScrolling = true

    /// Scales a view-point pan translation into a fraction of the Mac's
    /// screen. Not tied to any real display's resolution — it's a
    /// deliberately arbitrary reference that `sensitivity` scales.
    private let referenceSize = CGSize(width: 1600, height: 1000)

    var body: some View {
        NavigationStack {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))

                TrackpadSurface(
                    onTap: handleTap,
                    onRightTap: handleRightClick,
                    onPan: handlePan,
                    onScroll: handleScroll
                )

                if !hasInteracted {
                    Text("Tap to click • Two fingers to scroll")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .padding()
            .navigationTitle("Trackpad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Left Click") { sendClick(button: .left) }
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Right Click") { sendClick(button: .right) }
                }
            }
        }
    }

    private func markInteracted() {
        if !hasInteracted { hasInteracted = true }
    }

    private func handleTap(count: Int) {
        markInteracted()
        controlSession.sendInput(.mouseClick(MouseClickPayload(position: virtualCursor, button: .left, clickCount: UInt8(count))))
    }

    private func handleRightClick() {
        markInteracted()
        controlSession.sendInput(.mouseClick(MouseClickPayload(position: virtualCursor, button: .right, clickCount: 1)))
    }

    private func sendClick(button: MouseButton) {
        markInteracted()
        controlSession.sendInput(.mouseClick(MouseClickPayload(position: virtualCursor, button: button, clickCount: 1)))
    }

    private func handlePan(_ translation: CGPoint, state: UIGestureRecognizer.State) {
        guard state == .began || state == .changed else { return }
        markInteracted()

        let scale = 1.5 * sensitivity
        let deltaX = (translation.x * scale) / referenceSize.width
        let deltaY = (translation.y * scale) / referenceSize.height
        virtualCursor = NormalizedPoint(
            x: min(1, max(0, virtualCursor.x + deltaX)),
            y: min(1, max(0, virtualCursor.y + deltaY))
        )
        controlSession.sendInput(.mouseMove(MouseMovePayload(position: virtualCursor)))
    }

    private func handleScroll(_ delta: CGPoint) {
        markInteracted()
        let direction: Float = naturalScrolling ? 1 : -1
        controlSession.sendInput(.scroll(ScrollPayload(deltaX: Float(delta.x) * direction, deltaY: Float(-delta.y) * direction)))
    }
}

#Preview {
    TrackpadView(controlSession: DeviceSessionViewModel())
}
