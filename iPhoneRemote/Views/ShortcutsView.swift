import SwiftUI

struct ShortcutsView: View {
    @ObservedObject var controlSession: DeviceSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingCommand: SystemCommand?

    private static let sections: [(title: String, commands: [SystemCommand])] = [
        ("Navigation", [.missionControl, .launchpad, .spotlight, .appSwitcher, .showDesktop]),
        ("Media", [.playPause, .previousTrack, .nextTrack, .mute, .volumeUp, .volumeDown]),
        ("Power", [.lockScreen, .sleep, .restart, .shutdown])
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.commands, id: \.self) { command in
                            Button {
                                trigger(command)
                            } label: {
                                Label(command.label, systemImage: command.systemImage)
                                    .foregroundStyle(command == .shutdown || command == .restart ? .red : .primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingCommand.map { "\($0.label)?" } ?? "",
                isPresented: Binding(
                    get: { pendingCommand != nil },
                    set: { if !$0 { pendingCommand = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingCommand {
                    Button(pendingCommand.label, role: .destructive) {
                        send(pendingCommand)
                        self.pendingCommand = nil
                    }
                }
            }
        }
    }

    private func trigger(_ command: SystemCommand) {
        if command.requiresConfirmation {
            pendingCommand = command
        } else {
            send(command)
        }
    }

    private func send(_ command: SystemCommand) {
        controlSession.sendInput(.systemCommand(SystemCommandPayload(command: command)))
    }
}

#Preview {
    ShortcutsView(controlSession: DeviceSessionViewModel())
}
