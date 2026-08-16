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
    @State private var showingShortcuts = false
    @State private var showingDisconnectConfirmation = false

    var body: some View {
        GeometryReader { proxy in
            let contentGeometry = geometry(for: proxy.size)
            let hasSidePanel = usesSidePanel(for: proxy.size)
            let controlPanelWidth = sidePanelWidth(for: proxy.size)

            ZStack {
                Color.black.ignoresSafeArea()

                if let contentGeometry {
                    SampleBufferDisplayView(decoder: videoSession.decoder)
                        .frame(
                            width: contentGeometry.contentRect.width,
                            height: contentGeometry.contentRect.height
                        )
                        .position(
                            x: contentGeometry.contentRect.midX,
                            y: contentGeometry.contentRect.midY
                        )
                        .opacity(videoSession.isStreaming ? 1 : 0)
                }

                if videoSession.isStreaming,
                   let contentGeometry = geometry(for: proxy.size) {
                    TouchInputOverlay(
                        onTap: { location, count in
                            handleTap(
                                viewerLocation(location, in: contentGeometry.contentRect),
                                count: count,
                                viewSize: proxy.size
                            )
                        },
                        onLongPress: { location in
                            handleLongPress(
                                viewerLocation(location, in: contentGeometry.contentRect),
                                viewSize: proxy.size
                            )
                        },
                        onDragChange: { location, state in
                            handleDrag(
                                viewerLocation(location, in: contentGeometry.contentRect),
                                state: state,
                                viewSize: proxy.size
                            )
                        },
                        onScroll: { delta in handleScroll(delta) }
                    )
                    // Keep the UIKit gesture surface on the video itself.
                    // If it covers the black Fit margins, UIKit can reclaim
                    // hit testing after a dock update and block later taps.
                    .frame(
                        width: contentGeometry.contentRect.width,
                        height: contentGeometry.contentRect.height
                    )
                    .position(
                        x: contentGeometry.contentRect.midX,
                        y: contentGeometry.contentRect.midY
                    )
                    .clipped()
                    .zIndex(1)
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

                if videoSession.isStreaming, hasSidePanel {
                    RemoteSidePanel(
                        applications: controlSession.runningApplications,
                        controlSession: controlSession,
                        safeAreaInsets: proxy.safeAreaInsets,
                        onActivate: controlSession.activateApplication
                    )
                    .frame(width: controlPanelWidth, height: proxy.size.height)
                    .position(
                        x: proxy.size.width - controlPanelWidth / 2,
                        y: proxy.size.height / 2
                    )
                    .zIndex(2)
                }

                VStack {
                    if controlSession.connectionState == .reconnecting {
                        reconnectingBanner
                            .padding(.top, 8)
                    }
                    Spacer()
                    if videoSession.isStreaming {
                        remoteToolbar(showsTrackpadButton: !hasSidePanel)
                            .padding(.bottom, max(12, proxy.safeAreaInsets.bottom + 4))
                    }
                }
                .frame(width: contentGeometry?.contentRect.width ?? proxy.size.width)
                .position(
                    x: contentGeometry?.contentRect.midX ?? proxy.size.width / 2,
                    y: proxy.size.height / 2
                )
                .zIndex(3)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .onAppear {
            videoSession.start(endpoint: mac.endpoint)
            keyboardSession.send = { message in controlSession.sendInput(message) }
            controlSession.requestRunningApplications()
        }
        .onDisappear { videoSession.stop() }
        .sheet(isPresented: $showingTrackpad) {
            TrackpadView(controlSession: controlSession)
        }
        .sheet(isPresented: $showingDisplayPicker) {
            DisplayPickerView(videoSession: videoSession)
        }
        .sheet(isPresented: $showingShortcuts) {
            ShortcutsView(controlSession: controlSession)
        }
        .confirmationDialog("Disconnect from \(mac.name)?", isPresented: $showingDisconnectConfirmation, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                controlSession.disconnect()
                dismiss()
            }
        }
    }

    private var reconnectingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text("Reconnecting…")
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func remoteToolbar(showsTrackpadButton: Bool) -> some View {
        HStack(spacing: 28) {
            Button {
                showingKeyboard.toggle()
            } label: {
                Image(systemName: "keyboard")
            }

            if showsTrackpadButton {
                Button {
                    showingTrackpad = true
                } label: {
                    Image(systemName: "rectangle.and.hand.point.up.left")
                }
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
                    showingShortcuts = true
                } label: {
                    Label("Shortcuts", systemImage: "bolt")
                }
                Button {
                    controlSession.sendClipboardToMac()
                } label: {
                    Label("Send Clipboard to Mac", systemImage: "doc.on.clipboard")
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
        if usesSidePanel(for: viewSize) {
            let videoArea = CGSize(
                width: viewSize.width - sidePanelWidth(for: viewSize),
                height: viewSize.height
            )
            return VideoContentGeometry(
                contentSize: videoSize,
                viewSize: videoArea,
                scalingMode: .aspectFit,
                horizontalAlignment: .leading
            )
        }
        return VideoContentGeometry(
            contentSize: videoSize,
            viewSize: viewSize,
            scalingMode: .aspectFit
        )
    }

    private func usesSidePanel(for viewSize: CGSize) -> Bool {
        viewSize.width > viewSize.height * 1.3
    }

    private func sidePanelWidth(for viewSize: CGSize) -> CGFloat {
        guard usesSidePanel(for: viewSize) else { return 0 }
        return min(290, max(220, viewSize.width * 0.26))
    }

    private func viewerLocation(_ localLocation: CGPoint, in contentRect: CGRect) -> CGPoint {
        CGPoint(
            x: localLocation.x + contentRect.minX,
            y: localLocation.y + contentRect.minY
        )
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
