import SwiftUI
import UIKit

/// Landscape control column: apps stay at the top and a persistent relative
/// trackpad occupies the lower-right corner. The video never sits underneath
/// this panel, so UIKit gesture surfaces cannot steal its taps.
struct RemoteSidePanel: View {
    let applications: [RunningApplicationDescriptor]
    @ObservedObject var controlSession: DeviceSessionViewModel
    let safeAreaInsets: EdgeInsets
    let onActivate: (RunningApplicationDescriptor) -> Void

    @State private var hasUsedTrackpad = false
    @AppStorage(SettingsStore.Key.trackpadSensitivity) private var sensitivity: Double = 1.0
    @AppStorage(SettingsStore.Key.naturalScrolling) private var naturalScrolling = true

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 10) {
                applicationsSection
                    .frame(height: max(145, proxy.size.height * 0.48))

                trackpadSection
                    .frame(maxHeight: .infinity)
            }
            .padding(.leading, 10)
            .padding(.trailing, max(10, safeAreaInsets.trailing + 6))
            .padding(.top, max(8, safeAreaInsets.top + 4))
            .padding(.bottom, max(8, safeAreaInsets.bottom + 4))
        }
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Mac Apps", systemImage: "square.grid.2x2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 8)],
                    spacing: 9
                ) {
                    ForEach(applications) { application in
                        appButton(application)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var trackpadSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Trackpad", systemImage: "rectangle.and.hand.point.up.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.09))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }

                TrackpadSurface(
                    onTap: handleTap,
                    onRightTap: handleRightClick,
                    onPan: handlePan,
                    onScroll: handleScroll
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if !hasUsedTrackpad {
                    Text("Move • Tap • Two-finger scroll")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)
            .accessibilityLabel("Mac trackpad")

            HStack(spacing: 8) {
                clickButton("Left", button: .left)
                clickButton("Right", button: .right)
            }
        }
    }

    private func appButton(_ application: RunningApplicationDescriptor) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onActivate(application)
        } label: {
            VStack(spacing: 2) {
                if let image = UIImage(data: application.iconPNGData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 28))
                        .frame(width: 34, height: 34)
                }
                Text(application.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Circle()
                    .fill(application.isActive ? Color.cyan : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(application.name) on Mac")
        .accessibilityValue(application.isActive ? "Current application" : "")
    }

    private func clickButton(_ title: String, button: MouseButton) -> some View {
        Button(title) {
            hasUsedTrackpad = true
            controlSession.sendInput(.mouseClickCurrent(
                MouseClickCurrentPayload(button: button, clickCount: 1)
            ))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        .buttonStyle(.plain)
    }

    private func handleTap(count: Int) {
        hasUsedTrackpad = true
        controlSession.sendInput(.mouseClickCurrent(
            MouseClickCurrentPayload(button: .left, clickCount: UInt8(count))
        ))
    }

    private func handleRightClick() {
        hasUsedTrackpad = true
        controlSession.sendInput(.mouseClickCurrent(
            MouseClickCurrentPayload(button: .right, clickCount: 1)
        ))
    }

    private func handlePan(_ translation: CGPoint, state: UIGestureRecognizer.State) {
        guard state == .began || state == .changed else { return }
        hasUsedTrackpad = true
        let speed = hypot(translation.x, translation.y)
        let acceleration = min(2.0, 1.0 + speed / 12.0)
        let scale = 1.8 * sensitivity * acceleration
        controlSession.sendInput(.mouseMoveRelative(MouseMoveRelativePayload(
            deltaX: Float(translation.x * scale),
            deltaY: Float(translation.y * scale)
        )))
    }

    private func handleScroll(_ delta: CGPoint) {
        hasUsedTrackpad = true
        let direction: Float = naturalScrolling ? 1 : -1
        controlSession.sendInput(.scroll(ScrollPayload(
            deltaX: Float(delta.x) * direction,
            deltaY: Float(-delta.y) * direction
        )))
    }
}
