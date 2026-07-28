import SwiftUI

struct SettingsView: View {
    @AppStorage(TerminalService.applicationPathKey)
    private var terminalPath = "/System/Applications/Utilities/Terminal.app"
    @AppStorage("toolbar.showsSplit") private var toolbarShowsSplit = true
    @AppStorage("toolbar.showsTerminal") private var toolbarShowsTerminal = true
    @AppStorage("toolbar.showsOperations") private var toolbarShowsOperations = true
    @AppStorage("shortcut.commandPalette") private var commandPaletteKey = "p"
    @AppStorage("shortcut.terminal") private var terminalKey = "t"
    @AppStorage("gitStatusEnabled") private var gitStatusEnabled = false

    var body: some View {
        Form {
            Picker("Terminal application", selection: $terminalPath) {
                ForEach(TerminalService.installedApplications, id: \.path) { application in
                    Text(application.deletingPathExtension().lastPathComponent)
                        .tag(application.path)
                }
            }
            Text("Used by the toolbar and Open in Terminal actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Section("Toolbar") {
                Toggle("Split Pane", isOn: $toolbarShowsSplit)
                Toggle("Terminal", isOn: $toolbarShowsTerminal)
                Toggle("File Operations", isOn: $toolbarShowsOperations)
            }
            Section("Keyboard Shortcuts") {
                TextField("Command Palette (⌘⇧)", text: $commandPaletteKey)
                TextField("Open Terminal (⌘⌥)", text: $terminalKey)
                Text("Enter a single letter. Changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Folders") {
                Toggle("Show Git status badges", isOn: $gitStatusEnabled)
                Text("Disabled by default to avoid running Git in every folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: commandPaletteKey) { _, value in commandPaletteKey = sanitized(value, fallback: "p") }
        .onChange(of: terminalKey) { _, value in terminalKey = sanitized(value, fallback: "t") }
        .padding(20)
        .frame(width: 420)
    }

    private func sanitized(_ value: String, fallback: String) -> String {
        String(value.lowercased().filter(\.isLetter).prefix(1)).isEmpty
            ? fallback
            : String(value.lowercased().filter(\.isLetter).prefix(1))
    }
}
