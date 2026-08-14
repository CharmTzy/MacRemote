import SwiftUI

struct PairingCodeView: View {
    @ObservedObject var session: DeviceSessionViewModel
    let macName: String
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Enter the code shown on \(macName)")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("On your Mac, open Mac Remote and choose Pair New Device to see it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                TextField("847291", text: $code)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .focused($isFocused)
                    .onChange(of: code) { _, newValue in
                        code = String(newValue.filter(\.isNumber).prefix(6))
                    }
                    .padding(.horizontal, 40)

                if let error = session.pairingErrorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    isFocused = false
                    session.submitPairingCode(code)
                } label: {
                    if session.isSubmittingCode {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Pair")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(code.count != 6 || session.isSubmittingCode)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Pair iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        session.cancelPairing()
                        dismiss()
                    }
                }
            }
            .onAppear { isFocused = true }
            .onChange(of: session.connectionState) { _, newValue in
                if newValue == .connected { dismiss() }
            }
        }
    }
}

#Preview {
    PairingCodeView(session: DeviceSessionViewModel(), macName: "Wai's MacBook Air")
}
