import SwiftUI
import UIKit

/// Relative-movement trackpad, as an alternative to touching the mirrored
/// screen directly. Deltas are applied to the Mac's actual current cursor
/// position, so switching between this surface and the physical trackpad
/// does not cause jumps or drift.
///
/// Scope note: this mode moves the cursor and clicks, but doesn't drag —
/// distinguishing "move" from "click-and-drag" from touch alone needs a
/// hold-then-pan gesture this phase didn't build. Use Direct Touch (the
/// mirrored screen itself) for dragging.
struct TrackpadView: View {
    @ObservedObject var controlSession: DeviceSessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var hasInteracted = false
    @AppStorage(SettingsStore.Key.trackpadSensitivity) private var sensitivity: Double = 1.0
    @AppStorage(SettingsStore.Key.naturalScrolling) private var naturalScrolling = true

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
        controlSession.sendInput(.mouseClickCurrent(MouseClickCurrentPayload(button: .left, clickCount: UInt8(count))))
    }

    private func handleRightClick() {
        markInteracted()
        controlSession.sendInput(.mouseClickCurrent(MouseClickCurrentPayload(button: .right, clickCount: 1)))
    }

    private func sendClick(button: MouseButton) {
        markInteracted()
        controlSession.sendInput(.mouseClickCurrent(MouseClickCurrentPayload(button: button, clickCount: 1)))
    }

    private func handlePan(_ translation: CGPoint, state: UIGestureRecognizer.State) {
        guard state == .began || state == .changed else { return }
        markInteracted()

        let speed = hypot(translation.x, translation.y)
        let acceleration = min(2.0, 1.0 + speed / 12.0)
        let scale = 1.8 * sensitivity * acceleration
        controlSession.sendInput(.mouseMoveRelative(MouseMoveRelativePayload(
            deltaX: Float(translation.x * scale),
            deltaY: Float(translation.y * scale)
        )))
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
