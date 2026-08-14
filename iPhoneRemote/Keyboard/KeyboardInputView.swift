import SwiftUI

/// An invisible text field that captures the system keyboard, plus a
/// compact modifier/shortcut bar shown as its keyboard accessory. The
/// field itself shows nothing on screen — the point is relaying
/// keystrokes, and the result is visible on the Mac's mirrored screen, not
/// here.
struct KeyboardInputView: View {
    @ObservedObject var session: KeyboardInputSession
    @Binding var isPresented: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $session.fieldText)
            .autocorrectionDisabled(false)
            .textInputAutocapitalization(.never)
            .opacity(0)
            .frame(width: 1, height: 1)
            .focused($isFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            modifierButton(.command, label: "⌘")
                            modifierButton(.option, label: "⌥")
                            modifierButton(.control, label: "⌃")
                            modifierButton(.shift, label: "⇧")
                            Divider().frame(height: 20)
                            specialKeyButton(.escape, label: "esc")
                            specialKeyButton(.tab, label: "tab")
                            specialKeyButton(.leftArrow, systemImage: "arrow.left")
                            specialKeyButton(.downArrow, systemImage: "arrow.down")
                            specialKeyButton(.upArrow, systemImage: "arrow.up")
                            specialKeyButton(.rightArrow, systemImage: "arrow.right")
                        }
                    }
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
            .onChange(of: isPresented) { _, newValue in
                isFocused = newValue
            }
            .onAppear { isFocused = isPresented }
    }

    private func modifierButton(_ modifier: KeyModifiers, label: String) -> some View {
        let isActive = session.activeModifiers.contains(modifier)
        return Button {
            session.toggleModifier(modifier)
        } label: {
            Text(label)
                .frame(minWidth: 28)
                .fontWeight(isActive ? .bold : .regular)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
    }

    private func specialKeyButton(_ key: SpecialKey, label: String) -> some View {
        Button(label) {
            session.sendSpecialKey(key)
        }
    }

    private func specialKeyButton(_ key: SpecialKey, systemImage: String) -> some View {
        Button {
            session.sendSpecialKey(key)
        } label: {
            Image(systemName: systemImage)
        }
    }
}
