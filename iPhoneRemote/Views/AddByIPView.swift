import SwiftUI
import Network

struct AddByIPView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = DeviceSessionViewModel()

    @State private var host = ""
    @State private var port = String(ServiceConstants.defaultControlPort)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP Address", text: $host)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Find this in the Overview tab of Mac Remote on your Mac.")
                }

                if let error = session.lastErrorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add by IP Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if session.connectionState == .connecting {
                        ProgressView()
                    } else {
                        Button("Connect") { connect() }
                            .disabled(!isInputValid)
                    }
                }
            }
            .onChange(of: session.connectionState) { _, newValue in
                if newValue == .connected {
                    dismiss()
                }
            }
        }
    }

    private var isInputValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && UInt16(port) != nil
    }

    private func connect() {
        guard let portNumber = UInt16(port), let nwPort = NWEndpoint.Port(rawValue: portNumber) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        session.connect(to: endpoint, displayName: host)
    }
}

#Preview {
    AddByIPView()
}
