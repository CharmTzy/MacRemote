import SwiftUI
import UIKit

/// The screen-mirroring and direct-touch-control view — the most
/// important screen in the app. The video fills the whole screen; the
/// only persistent chrome is a small translucent toolbar, keyboard and
/// trackpad get direct buttons since they're used constantly, and
/// everything else (displays, disconnect) lives behind a single menu
/// rather than crowding the bar.
struct RemoteViewerView: View {
    let mac: DiscoveredMac
    @ObservedObject var controlSession: DeviceSessionViewModel
    @StateObject private var videoSession = VideoSessionViewModel()
    @StateObject private var keyboardSession = KeyboardInputSession()
    @Environment(\.dismiss) private var dismiss
    @State private var isDragging = false
    @State private var showingKeyboard = false
    @State private var showingTrackpad = false
    @State private var showingDisplayPicker = false
    @State private var showingDisconnectConfirmation = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                SampleBufferDisplayView(decoder: videoSession.decoder)
                    .ignoresSafeArea()
                    .opacity(videoSession.isStreaming ? 1 : 0)

                if videoSession.isStreaming {
                    TouchInputOverlay(
                        onTap: { location, count in handleTap(location, count: count, viewSize: proxy.size) },
                        onLongPress: { location in handleLongPress(location, viewSize: proxy.size) },
                        onDragChange: { location, state in handleDrag(location, state: state, viewSize: proxy.size) },
                        onScroll: { delta in handleScroll(delta) }
                    )
                    .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        if let error = videoSession.errorMessage {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundStyle(.white)
                            Text(error)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else {
                            ProgressView()
                                .tint(.white)
                            Text("Connecting to \(mac.name)…")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }

                KeyboardInputView(session: keyboardSession, isPresented: $showingKeyboard)

                VStack {
                    Spacer()
                    if videoSession.isStreaming {
                        remoteToolbar
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .onAppear {
            videoSession.start(endpoint: mac.endpoint)
            keyboardSession.send = { message in controlSession.sendInput(message) }
        }
        .onDisappear { videoSession.stop() }
        .sheet(isPresented: $showingTrackpad) {
            TrackpadView(controlSession: controlSession)
        }
        .sheet(isPresented: $showingDisplayPicker) {
            DisplayPickerView(videoSession: videoSession)
        }
        .confirmationDialog("Disconnect from \(mac.name)?", isPresented: $showingDisconnectConfirmation, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                controlSession.disconnect()
                dismiss()
            }
        }
    }

    private var remoteToolbar: some View {
        HStack(spacing: 28) {
            Button {
                showingKeyboard.toggle()
            } label: {
                Image(systemName: "keyboard")
            }

            Button {
                showingTrackpad = true
            } label: {
                Image(systemName: "rectangle.and.hand.point.up.left")
            }

            Menu {
                if videoSession.availableDisplays.count > 1 {
                    Button {
                        showingDisplayPicker = true
                    } label: {
                        Label("Displays", systemImage: "display")
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                Button(role: .destructive) {
                    showingDisconnectConfirmation = true
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func geometry(for viewSize: CGSize) -> VideoContentGeometry? {
        guard let videoSize = videoSession.videoSize else { return nil }
        return VideoContentGeometry(contentSize: videoSize, viewSize: viewSize)
    }

    private func handleTap(_ location: CGPoint, count: Int, viewSize: CGSize) {
        guard let position = geometry(for: viewSize)?.normalizedPoint(for: location) else { return }
        controlSession.sendInput(.mouseClick(MouseClickPayload(position: position, button: .left, clickCount: UInt8(count))))
    }

    private func handleLongPress(_ location: CGPoint, viewSize: CGSize) {
        guard let position = geometry(for: viewSize)?.normalizedPoint(for: location) else { return }
        controlSession.sendInput(.mouseClick(MouseClickPayload(position: position, button: .right, clickCount: 1)))
    }

    private func handleDrag(_ location: CGPoint, state: UIGestureRecognizer.State, viewSize: CGSize) {
        guard let position = geometry(for: viewSize)?.normalizedPoint(for: location) else { return }
        switch state {
        case .began:
            isDragging = true
            controlSession.sendInput(.mouseButton(MouseButtonPayload(position: position, button: .left, isDown: true)))
        case .changed:
            guard isDragging else { return }
            controlSession.sendInput(.mouseDragged(MouseDraggedPayload(position: position, button: .left)))
        case .ended, .cancelled, .failed:
            guard isDragging else { return }
            isDragging = false
            controlSession.sendInput(.mouseButton(MouseButtonPayload(position: position, button: .left, isDown: false)))
        default:
            break
        }
    }

    private func handleScroll(_ delta: CGPoint) {
        controlSession.sendInput(.scroll(ScrollPayload(deltaX: Float(delta.x), deltaY: Float(-delta.y))))
    }
}
