import SwiftUI
import UIKit

#if DEBUG
/// A deterministic, network-free presentation of the real landscape control
/// layout. It is only shown when the app is launched with
/// `--demo-remote-control`, which keeps screenshots reproducible without
/// changing the normal app experience.
struct RemoteControlDemoView: View {
    @StateObject private var controlSession = DeviceSessionViewModel()

    private let applications = [
        RunningApplicationDescriptor(bundleIdentifier: "com.apple.finder", name: "Finder", iconPNGData: Data(), isActive: true),
        RunningApplicationDescriptor(bundleIdentifier: "com.apple.Safari", name: "Safari", iconPNGData: Data(), isActive: false),
        RunningApplicationDescriptor(bundleIdentifier: "com.apple.Notes", name: "Notes", iconPNGData: Data(), isActive: false),
        RunningApplicationDescriptor(bundleIdentifier: "com.apple.Music", name: "Music", iconPNGData: Data(), isActive: false),
        RunningApplicationDescriptor(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode", iconPNGData: Data(), isActive: false),
        RunningApplicationDescriptor(bundleIdentifier: "com.apple.Terminal", name: "Terminal", iconPNGData: Data(), isActive: false),
    ]

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(max(proxy.size.width * 0.24, 236), 320)

            ZStack(alignment: .trailing) {
                demoDesktop
                    .frame(width: proxy.size.width - panelWidth, height: proxy.size.height)
                    .frame(maxWidth: .infinity, alignment: .leading)

                RemoteSidePanel(
                    applications: applications,
                    controlSession: controlSession,
                    safeAreaInsets: proxy.safeAreaInsets,
                    onActivate: { _ in }
                )
                .frame(width: panelWidth, height: proxy.size.height)

                HStack(spacing: 28) {
                    Image(systemName: "keyboard")
                    Image(systemName: "ellipsis.circle")
                }
                .font(.title3)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .padding(.trailing, panelWidth + 22)
                .padding(.bottom, max(12, proxy.safeAreaInsets.bottom + 4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }

    private var demoDesktop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.13, blue: 0.29), Color(red: 0.05, green: 0.55, blue: 0.67)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.cyan.opacity(0.2))
                .frame(width: 420)
                .blur(radius: 30)
                .offset(x: -220, y: 150)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Circle().fill(.yellow).frame(width: 10, height: 10)
                    Circle().fill(.green).frame(width: 10, height: 10)
                    Text("Mac Remote")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text("Connected securely")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(.black.opacity(0.48))

                HStack(spacing: 24) {
                    Image(systemName: "macbook.and.iphone")
                        .font(.system(size: 74, weight: .light))
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Mac. In your hands.")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Full display • Quick apps • Precise trackpad")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(34)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        }
        .clipped()
    }
}
#endif
