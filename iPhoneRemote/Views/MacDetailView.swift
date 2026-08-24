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
    @State private var isSendingWakeSignal = false
    @State private var wakeStatusMessage: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 15) {
                    Image(systemName: "macbook")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 62, height: 62)
                        .background(BrandTheme.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(mac.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(mac.model ?? "Mac")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(statusLabel, systemImage: mac.state == .offline ? "moon.zzz.fill" : "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(mac.state == .offline ? Color.orange : BrandTheme.cyan)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                .brandCard()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Status", value: statusLabel)
                if let progress = session.connectProgressMessage {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = session.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !mac.internetCandidates.isEmpty {
                    Text("This Mac can also be reached over the internet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if mac.state == .offline {
                Section {
                    Button(action: wakeMac) {
                        HStack {
                            Label("Wake Mac", systemImage: "power")
                            Spacer()
                            if isSendingWakeSignal { ProgressView() }
                        }
                    }
                    .disabled(isSendingWakeSignal || mac.wakeMACAddress == nil)

                    if let wakeStatusMessage {
                        Text(wakeStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if mac.wakeMACAddress == nil {
                        Text("Connect once while the Mac is awake to save its wake information.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Remote Wake")
                } footer: {
                    Text("Works when the Mac is sleeping, connected to power, and Wake for network access is enabled. A fully shut-down MacBook cannot receive a network wake signal.")
                }
            }

            Section {
                Button {
                    if session.connectionState == .connected || session.connectionState == .reconnecting {
                        session.disconnect()
                    } else {
                        session.connect(
                            to: mac.endpoint,
                            internetCandidates: mac.internetCandidates,
                            displayName: mac.name,
                            primaryLabel: mac.state == .offline ? "Last local address" : "Nearby (Bonjour)"
                        )
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
                        Label("Disconnect", systemImage: "xmark.circle")
                    default:
                        Label("Connect to Mac", systemImage: "bolt.fill")
                    }
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(BrandTheme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(session.connectionState == .connecting)
            }

            if session.connectionState == .connected {
                Section {
                    Button {
                        showingViewer = true
                    } label: {
                        Label("Start Remote Control", systemImage: "rectangle.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTheme.blue)
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
        .scrollContentBackground(.hidden)
        .background(BrandTheme.backgroundGradient.ignoresSafeArea())
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
            RemoteViewerView(
                mac: mac,
                endpoint: session.activeEndpoint ?? mac.endpoint,
                controlSession: session
            )
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                fileTransfer.send(fileURL: url, to: session.activeEndpoint ?? mac.endpoint)
            }
        }
        .onChange(of: session.connectionState) { _, newValue in
            guard newValue == .connected, let deviceID = session.macDeviceID else { return }
            TrustedDeviceStore().updateNetworkMetadata(
                deviceID: deviceID,
                ipv4Address: mac.ipv4Address,
                broadcastAddress: mac.broadcastAddress,
                wakeMACAddress: mac.wakeMACAddress
            )
        }
    }

    private var statusLabel: String {
        if mac.state == .offline, session.connectionState == .available {
            return mac.internetCandidates.isEmpty ? "Offline" : "Away — reachable over Internet"
        }
        return session.connectionState.label
    }

    private func wakeMac() {
        guard let macAddress = mac.wakeMACAddress else { return }
        isSendingWakeSignal = true
        wakeStatusMessage = nil
        Task {
            do {
                try await WakeOnLANService.wake(macAddress: macAddress, broadcastAddress: mac.broadcastAddress)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                wakeStatusMessage = "Wake signal sent. The Mac usually becomes available within 10–30 seconds."
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                wakeStatusMessage = (error as? LocalizedError)?.errorDescription ?? "The wake signal couldn't be sent."
            }
            isSendingWakeSignal = false
        }
    }
}

#Preview {
    let previewEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: 53511)!)
    return NavigationStack {
        MacDetailView(mac: DiscoveredMac(id: "preview", name: "Wai's MacBook Air", model: "Mac15,6", endpoint: previewEndpoint, state: .available))
    }
}
