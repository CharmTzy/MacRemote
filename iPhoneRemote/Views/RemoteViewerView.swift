import SwiftUI

/// The screen-mirroring view. Phase 3's job is just getting the Mac's
/// screen to appear here reliably — the minimal chrome (a single Close
/// button) is a placeholder for Phase 6's full remote toolbar (keyboard,
/// trackpad, shortcuts, display picker), not the finished design.
struct RemoteViewerView: View {
    let mac: DiscoveredMac
    @StateObject private var videoSession = VideoSessionViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SampleBufferDisplayView(decoder: videoSession.decoder)
                .ignoresSafeArea()
                .opacity(videoSession.isStreaming ? 1 : 0)

            if !videoSession.isStreaming {
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

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .onAppear { videoSession.start(endpoint: mac.endpoint) }
        .onDisappear { videoSession.stop() }
    }
}
