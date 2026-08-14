import SwiftUI

/// Informational — which display an iPhone streams is chosen from the
/// iPhone's side (Displays picker in the remote viewer), matching how
/// switching there works without reconnecting. This screen just shows
/// what's available and requires the same Screen Recording permission the
/// Permissions tab already surfaces.
struct DisplayView: View {
    @State private var displays: [DisplayCatalog.DisplayInfo] = []
    @State private var loadError: String?

    var body: some View {
        Form {
            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                }
            } else if displays.isEmpty {
                Section {
                    Text("No displays found.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(displays) { display in
                        LabeledContent(display.name, value: "\(display.width) × \(display.height)")
                    }
                } footer: {
                    Text("An iPhone chooses which display to view from the remote viewer's Displays menu — switching there doesn't require reconnecting.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            displays = try await DisplayCatalog.availableDisplays()
            loadError = nil
        } catch {
            loadError = "Couldn't list displays. Grant Screen Recording in the Permissions tab, then reopen this tab."
        }
    }
}

#Preview {
    DisplayView()
}
