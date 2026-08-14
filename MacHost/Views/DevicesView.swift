import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var sessionManager: HostSessionManager
    @State private var showingPairSheet = false
    @State private var showingForgetAllConfirmation = false
    @State private var pairedDevices: [PairedDeviceRecord] = []

    var body: some View {
        List {
            Section("Connected") {
                if sessionManager.connectedPeers.isEmpty {
                    Text("No devices connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionManager.connectedPeers) { peer in
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(peer.name)
                                Text(peer.model)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(peer.state.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !sessionManager.activeTransfers.isEmpty {
                Section("File Transfers") {
                    ForEach(Array(sessionManager.activeTransfers.values)) { transfer in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transfer.filename)
                            if let failureReason = transfer.failureReason {
                                Text(failureReason)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else if transfer.isComplete {
                                Label("Saved to Downloads/Mac Remote", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView(value: transfer.fractionComplete)
                            }
                        }
                    }
                }
            }

            Section("Paired Devices") {
                if pairedDevices.isEmpty {
                    Text("No paired devices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pairedDevices) { device in
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("Paired \(device.pairedAt, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: forget)
                }
            }
        }
        .navigationTitle("Devices")
        .toolbar {
            ToolbarItem {
                Button {
                    showingPairSheet = true
                } label: {
                    Label("Pair New Device", systemImage: "plus")
                }
            }
            ToolbarItem {
                Menu {
                    Button("Forget All Paired Devices", role: .destructive) {
                        showingForgetAllConfirmation = true
                    }
                    .disabled(pairedDevices.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingPairSheet) {
            PairNewDeviceView(pairingCoordinator: sessionManager.pairingCoordinator)
        }
        .confirmationDialog(
            "Forget All Paired Devices?",
            isPresented: $showingForgetAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget All Paired Devices", role: .destructive) {
                sessionManager.forgetAllDevices()
                refresh()
            }
        } message: {
            Text("Every paired iPhone will need to pair again, with a new code, before it can connect.")
        }
        .onAppear(perform: refresh)
        .onChange(of: sessionManager.connectedPeers) { _, _ in refresh() }
    }

    private func refresh() {
        pairedDevices = sessionManager.pairedDevices()
    }

    private func forget(at offsets: IndexSet) {
        for index in offsets {
            sessionManager.forgetDevice(id: pairedDevices[index].id)
        }
        refresh()
    }
}

#Preview {
    DevicesView().environmentObject(HostSessionManager())
}
