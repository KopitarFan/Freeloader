import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var operations: FileOperationManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showsSplitPane") private var showsSplitPane = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let commands = [
        "New File", "New Folder", "New Tab", "Duplicate Tab",
        "Open in Terminal", "File Operations", "Toggle Split Pane",
        "Toggle Folder Tree", "Toggle Hidden Files", "List View",
        "Compact View", "Icon View", "Home", "Reload"
    ]

    var body: some View {
        VStack(spacing: 12) {
            TextField("Type a command", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            List(filteredCommands, id: \.self) { command in
                Button {
                    run(command)
                    dismiss()
                } label: {
                    Text(command)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 460, height: 420)
        .onAppear { searchFocused = true }
    }

    private var filteredCommands: [String] {
        guard !query.isEmpty else { return commands }
        return commands.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func run(_ command: String) {
        switch command {
        case "New File": browser.requestNewFile()
        case "New Folder": browser.showsNewFolderPrompt = true
        case "New Tab": browser.newTab()
        case "Duplicate Tab": browser.duplicateTab(browser.activeTabID)
        case "Open in Terminal": TerminalService.open(at: browser.currentURL)
        case "File Operations": operations.showsDetails = true
        case "Toggle Split Pane": showsSplitPane.toggle()
        case "Toggle Folder Tree": browser.showsTree.toggle()
        case "Toggle Hidden Files": browser.toggleHiddenFiles()
        case "List View": browser.viewMode = .list
        case "Compact View": browser.viewMode = .compact
        case "Icon View": browser.viewMode = .icons
        case "Home": browser.navigate(to: FileManager.default.homeDirectoryForCurrentUser)
        case "Reload": browser.reload()
        default: break
        }
    }
}
