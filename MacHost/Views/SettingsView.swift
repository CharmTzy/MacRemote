import SwiftUI
import Foundation

struct SettingsView: View {
    @EnvironmentObject private var sessionManager: HostSessionManager
    @State private var showingForgetAllConfirmation = false
    @AppStorage(SettingsStore.Key.clipboardSyncEnabled) private var clipboardSyncEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Clipboard Sync", isOn: $clipboardSyncEnabled)
            } footer: {
                Text("When on, copying text on either device makes it available to paste on the other.")
            }

            Section {
                Button("Forget All Paired Devices", role: .destructive) {
                    showingForgetAllConfirmation = true
                }
                .disabled(sessionManager.pairedDevices().isEmpty)
            } header: {
                Text("Security")
            } footer: {
                Text("Every paired iPhone will need to pair again, with a new code, before it can connect. Manage individual devices from the Devices tab.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.shortVersionString)
                LabeledContent("Build", value: Bundle.main.buildNumber)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Forget All Paired Devices?",
            isPresented: $showingForgetAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget All Paired Devices", role: .destructive) {
                sessionManager.forgetAllDevices()
            }
        }
    }
}

private extension Bundle {
    var shortVersionString: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
}

#Preview {
    SettingsView().environmentObject(HostSessionManager())
}
