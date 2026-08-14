import SwiftUI

struct PairNewDeviceView: View {
    @ObservedObject var pairingCoordinator: PairingCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Text("Pair iPhone")
                    .font(.title2)
                Text("Enter this code on your iPhone:")
                    .foregroundStyle(.secondary)
                Text(pairingCoordinator.formattedCode ?? " ")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.top, 4)
            }

            if let expiresAt = pairingCoordinator.expiresAt {
                Text("Expires \(expiresAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                pairingCoordinator.stopPairing()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(minWidth: 360, minHeight: 320)
        .onAppear { pairingCoordinator.startPairing() }
        .onChange(of: pairingCoordinator.activeCode) { _, newValue in
            if newValue == nil { dismiss() }
        }
    }
}

#Preview {
    PairNewDeviceView(pairingCoordinator: PairingCoordinator())
}
