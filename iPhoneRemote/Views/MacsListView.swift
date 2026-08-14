import SwiftUI

struct MacsListView: View {
    @StateObject private var discovery = DiscoveryViewModel()
    @State private var showingAddByIP = false

    var body: some View {
        NavigationStack {
            List {
                Section("Nearby") {
                    if discovery.discoveredMacs.isEmpty {
                        HStack(spacing: 8) {
                            if discovery.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(discovery.isSearching ? "Searching for Macs…" : "No Macs found")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(discovery.discoveredMacs) { mac in
                            NavigationLink(value: mac) {
                                MacRow(mac: mac)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingAddByIP = true
                    } label: {
                        Label("Add by IP Address", systemImage: "network")
                    }
                }
            }
            .navigationTitle("Macs")
            .navigationDestination(for: DiscoveredMac.self) { mac in
                MacDetailView(mac: mac)
            }
            .sheet(isPresented: $showingAddByIP) {
                AddByIPView()
            }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
        }
    }
}

private struct MacRow: View {
    let mac: DiscoveredMac

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "macbook")
                .foregroundStyle(.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name)
                if let model = mac.model {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(mac.state.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MacsListView()
}
