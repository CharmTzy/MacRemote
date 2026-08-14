import SwiftUI

struct DisplayPickerView: View {
    @ObservedObject var videoSession: VideoSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(videoSession.availableDisplays) { display in
                Button {
                    videoSession.selectDisplay(display.id)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display.name)
                                .foregroundStyle(.primary)
                            Text("\(display.width) × \(display.height)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if display.id == videoSession.selectedDisplayID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Displays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
