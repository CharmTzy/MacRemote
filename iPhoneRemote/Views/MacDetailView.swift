import SwiftUI
import Network
import UniformTypeIdentifiers

struct MacDetailView: View {
    let mac: DiscoveredMac
    @StateObject private var session = DeviceSessionViewModel()
    @StateObject private var fileTransfer = FileTransferViewModel()
    @State private var showingForgetConfirmation = false
    @State private var showingViewer = false
    @State private var showingFileImporter = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mac.name)
                        .font(.title2)
                    if let model = mac.model {
                        Text(model)
                            .foregroundStyle(.secondary)
                    }
                    Text("Local Network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Status", value: session.connectionState.label)
                if let error = session.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    if session.connectionState == .connected || session.connectionState == .reconnecting {
                        session.disconnect()
                    } else {
                        session.connect(to: mac.endpoint, displayName: mac.name)
                    }
                } label: {
                    switch session.connectionState {
                    case .connecting:
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    case .reconnecting:
                        HStack {
                            Spacer()
                            ProgressView()
                            Text("Cancel Reconnecting")
                            Spacer()
                        }
                    case .connected:
                        Text("Disconnect")
                    default:
                        Text("Connect")
                    }
                }
                .disabled(session.connectionState == .connecting)
            }

            if session.connectionState == .connected {
                Section {
                    Button {
                        showingViewer = true
                    } label: {
                        Label("View Screen", systemImage: "rectangle.on.rectangle")
                    }
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Send File…", systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(fileTransfer.activeTransfer != nil && fileTransfer.activeTransfer?.isComplete == false && fileTransfer.activeTransfer?.failureReason == nil)
                }
            }

            if let transfer = fileTransfer.activeTransfer {
                Section("File Transfer") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(transfer.filename)
                        if let failureReason = transfer.failureReason {
                            Text(failureReason)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if transfer.isComplete {
                            Label("Sent", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView(value: transfer.fractionComplete)
                        }
                    }
                    .swipeActions {
                        Button("Dismiss") { fileTransfer.dismiss() }
                    }
                }
            }

            if session.macDeviceID != nil {
                Section {
                    Button("Forget This Mac", role: .destructive) {
                        showingForgetConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(mac.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { session.pairingCodeNeeded },
            set: { if !$0 { session.cancelPairing() } }
        )) {
            PairingCodeView(session: session, macName: mac.name)
        }
        .confirmationDialog(
            "Forget \(mac.name)?",
            isPresented: $showingForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget This Mac", role: .destructive) {
                if let deviceID = session.macDeviceID {
                    session.disconnect()
                    try? TrustedDeviceStore().remove(deviceID: deviceID)
                }
            }
        } message: {
            Text("Your iPhone will need to pair with this Mac again before it can connect.")
        }
        .fullScreenCover(isPresented: $showingViewer) {
            RemoteViewerView(mac: mac, controlSession: session)
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                fileTransfer.send(fileURL: url, to: mac.endpoint)
            }
        }
    }
}

#Preview {
    let previewEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: 53511)!)
    return NavigationStack {
        MacDetailView(mac: DiscoveredMac(id: "preview", name: "Wai's MacBook Air", model: "Mac15,6", endpoint: previewEndpoint, state: .available))
    }
}
