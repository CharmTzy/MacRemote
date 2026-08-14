import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var sessionManager: HostSessionManager

    var body: some View {
        Group {
            if sessionManager.connectedPeers.isEmpty {
                ContentUnavailableView(
                    "No Devices Connected",
                    systemImage: "iphone",
                    description: Text("Open Mac Remote on your iPhone and select this Mac to connect.")
                )
            } else {
                List(sessionManager.connectedPeers) { peer in
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
        .navigationTitle("Devices")
    }
}

#Preview {
    DevicesView().environmentObject(HostSessionManager())
}
