import SwiftUI
import AppKit

struct PermissionsView: View {
    @StateObject private var viewModel = PermissionsViewModel()

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Screen Recording",
                    detail: "Needed to stream this Mac's screen to your iPhone.",
                    granted: viewModel.screenRecordingGranted,
                    request: viewModel.requestScreenRecording,
                    openSettings: viewModel.openScreenRecordingSettings
                )
                permissionRow(
                    title: "Accessibility",
                    detail: "Needed to control the mouse and keyboard from your iPhone.",
                    granted: viewModel.accessibilityGranted,
                    request: viewModel.requestAccessibility,
                    openSettings: viewModel.openAccessibilitySettings
                )
            } footer: {
                Text("Mac Remote cannot stream your screen or accept control input until both permissions are allowed.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
        .onAppear { viewModel.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool, request: @escaping () -> Void, openSettings: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(granted ? "Allowed" : "Required", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(granted ? Color.secondary : Color.orange)
            }
            if !granted {
                Button("Open System Settings") {
                    request()
                    openSettings()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PermissionsView()
}
