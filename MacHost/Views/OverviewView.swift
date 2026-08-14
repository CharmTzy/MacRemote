import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var sessionManager: HostSessionManager
    @StateObject private var viewModel = OverviewViewModel()
    @StateObject private var permissions = PermissionsViewModel()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "macbook")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac Remote")
                            .font(.title2)
                        Text(sessionManager.isAdvertising ? "Ready for Connections" : "Not Visible on the Network")
                            .font(.subheadline)
                            .foregroundStyle(sessionManager.isAdvertising ? .secondary : .orange)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Computer Name") {
                Text(viewModel.computerName)
            }

            Section("Network") {
                LabeledContent("Address", value: viewModel.ipAddress ?? "Unavailable")
                LabeledContent("Port", value: String(ServiceConstants.defaultControlPort))
            }

            Section("Connected Devices") {
                if sessionManager.connectedPeers.isEmpty {
                    Text("No devices connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionManager.connectedPeers) { peer in
                        LabeledContent(peer.name, value: peer.model)
                    }
                }
            }

            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    statusLabel(permissions.screenRecordingGranted)
                }
                LabeledContent("Accessibility") {
                    statusLabel(permissions.accessibilityGranted)
                }
                if !permissions.allPermissionsGranted {
                    Text("Open the Permissions tab to finish setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            viewModel.refresh()
            permissions.refresh()
        }
    }

    @ViewBuilder
    private func statusLabel(_ granted: Bool) -> some View {
        Label(granted ? "Allowed" : "Required", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(granted ? .secondary : .orange)
            .font(.callout)
    }
}

#Preview {
    OverviewView().environmentObject(HostSessionManager())
}
