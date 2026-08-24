import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var sessionManager: HostSessionManager
    @EnvironmentObject private var reachability: ReachabilityController
    @StateObject private var viewModel = OverviewViewModel()
    @StateObject private var permissions = PermissionsViewModel()

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 14)]

    var body: some View {
        ZStack {
            BrandTheme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero

                    LazyVGrid(columns: columns, spacing: 14) {
                        metricCard(
                            title: "Network",
                            value: viewModel.ipAddress ?? "Unavailable",
                            detail: "Port \(ServiceConstants.defaultControlPort)",
                            icon: "network"
                        )
                        metricCard(
                            title: "Anywhere Access",
                            value: anywhereValue,
                            detail: anywhereDetail,
                            icon: "globe"
                        )
                        metricCard(
                            title: "Remote Wake",
                            value: LocalNetworkInfo.primaryInterface()?.macAddress == nil ? "Unavailable" : "Ready",
                            detail: "Keep this Mac connected to power",
                            icon: "power"
                        )
                        metricCard(
                            title: "Connected",
                            value: "\(sessionManager.connectedPeers.count)",
                            detail: sessionManager.connectedPeers.isEmpty ? "No iPhones connected" : "Secure session active",
                            icon: "iphone.radiowaves.left.and.right"
                        )
                    }

                    permissionsCard

                    if !sessionManager.connectedPeers.isEmpty {
                        connectedDevicesCard
                    }
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(28)
            }
        }
        .navigationTitle("Overview")
        .onAppear {
            viewModel.refresh()
            permissions.refresh()
        }
    }

    private var anywhereValue: String {
        switch reachability.status {
        case .checking: return "Checking…"
        case .active: return "Ready"
        case .degraded: return "LAN only"
        case .unavailable: return "Limited"
        }
    }

    private var anywhereDetail: String {
        switch reachability.status {
        case .checking:
            return "Finding ways to reach this Mac"
        case .active(let summary):
            return "Reachable from the internet · \(summary)"
        case .degraded(let summary):
            return "\(summary) — same-Wi-Fi control still works"
        case .unavailable(let reason):
            return reason
        }
    }

    private var hero: some View {
        HStack(spacing: 18) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 35, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .background(BrandTheme.accentGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Mac Remote")
                    .font(.largeTitle.weight(.bold))
                Text(viewModel.computerName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Label(
                    sessionManager.isAdvertising ? "Ready for secure connections" : "Not visible on the network",
                    systemImage: sessionManager.isAdvertising ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(sessionManager.isAdvertising ? BrandTheme.cyan : Color.orange)
            }
            Spacer()
        }
        .padding(22)
        .brandCard(cornerRadius: 26)
    }

    private func metricCard(title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(BrandTheme.cyan)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .brandCard()
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Permissions", systemImage: "lock.shield.fill")
                .font(.headline)
            permissionRow("Screen Recording", granted: permissions.screenRecordingGranted)
            Divider().overlay(Color.primary.opacity(0.12))
            permissionRow("Accessibility", granted: permissions.accessibilityGranted)
            if !permissions.allPermissionsGranted {
                Text("Open the Permissions tab to finish setup before controlling this Mac.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .brandCard()
    }

    private var connectedDevicesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Active iPhones", systemImage: "iphone")
                .font(.headline)
            ForEach(sessionManager.connectedPeers) { peer in
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.name).fontWeight(.medium)
                        Text(peer.model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Encrypted")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTheme.cyan)
                }
            }
        }
        .padding(20)
        .brandCard()
    }

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(granted ? "Allowed" : "Required", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? BrandTheme.cyan : Color.orange)
                .font(.callout.weight(.semibold))
        }
    }
}

#Preview { OverviewView().environmentObject(HostSessionManager()) }
