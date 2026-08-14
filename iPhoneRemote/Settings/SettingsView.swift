import SwiftUI
import Foundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsStore.Key.streamingQuality) private var quality: QualityProfile = .auto
    @AppStorage(SettingsStore.Key.trackpadSensitivity) private var trackpadSensitivity: Double = 1.0
    @AppStorage(SettingsStore.Key.naturalScrolling) private var naturalScrolling = true
    @State private var pairedMacs: [PairedDeviceRecord] = []
    @State private var showingForgetAllConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Streaming") {
                    Picker("Quality", selection: $quality) {
                        ForEach(QualityProfile.allCases) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }
                    if quality != .auto {
                        LabeledContent("Detail", value: quality.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Trackpad Sensitivity")
                        Slider(value: $trackpadSensitivity, in: 0.5...2.0, step: 0.1)
                    }
                    Toggle("Natural Scrolling", isOn: $naturalScrolling)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Applies to Trackpad mode. Direct Touch always maps 1:1 to the Mac's screen.")
                }

                Section("Security") {
                    if pairedMacs.isEmpty {
                        Text("No paired Macs")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pairedMacs) { mac in
                            VStack(alignment: .leading) {
                                Text(mac.name)
                                Text("Paired \(mac.pairedAt, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: forget)
                    }
                    if !pairedMacs.isEmpty {
                        Button("Forget All Macs", role: .destructive) {
                            showingForgetAllConfirmation = true
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.shortVersionString)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Forget All Macs?",
                isPresented: $showingForgetAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Forget All Macs", role: .destructive) {
                    try? TrustedDeviceStore().removeAll()
                    refresh()
                }
            } message: {
                Text("Your iPhone will need to pair again, with a new code, before it can connect to any of them.")
            }
            .onAppear(perform: refresh)
        }
    }

    private func refresh() {
        pairedMacs = TrustedDeviceStore().all()
    }

    private func forget(at offsets: IndexSet) {
        for index in offsets {
            try? TrustedDeviceStore().remove(deviceID: pairedMacs[index].id)
        }
        refresh()
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
    SettingsView()
}
