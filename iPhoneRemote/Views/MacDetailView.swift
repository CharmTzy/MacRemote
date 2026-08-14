import SwiftUI
import Network

struct MacDetailView: View {
    let mac: DiscoveredMac
    @StateObject private var session = DeviceSessionViewModel()

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
                    if session.connectionState == .connected {
                        session.disconnect()
                    } else {
                        session.connect(to: mac.endpoint, displayName: mac.name)
                    }
                } label: {
                    if session.connectionState == .connecting {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text(session.connectionState == .connected ? "Disconnect" : "Connect")
                    }
                }
                .disabled(session.connectionState == .connecting)
            }
        }
        .navigationTitle(mac.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let previewEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: 53511)!)
    return NavigationStack {
        MacDetailView(mac: DiscoveredMac(id: "preview", name: "Wai's MacBook Air", model: "Mac15,6", endpoint: previewEndpoint, state: .available))
    }
}
