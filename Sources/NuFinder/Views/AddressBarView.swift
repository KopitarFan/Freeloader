import SwiftUI

struct AddressBarView: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var isFocused: Bool
    @State private var suggestions: [URL] = []
    @State private var selectedSuggestion = 0
    @State private var allowsSuggestions = false

    var body: some View {
        TextField("Enter a path", text: $browser.addressText)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .frame(minWidth: 240)
            .onSubmit {
                if suggestions.indices.contains(selectedSuggestion) {
                    browser.navigate(to: suggestions[selectedSuggestion])
                } else {
                    browser.navigateFromAddress()
                }
                isFocused = false
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    allowsSuggestions = true
                    updateSuggestions()
                }
            )
            .onChange(of: browser.addressText) { _, _ in
                if allowsSuggestions { updateSuggestions() }
            }
            .onChange(of: browser.addressFocusToken) { _, _ in
                allowsSuggestions = true
                isFocused = true
            }
            .onChange(of: isFocused) { _, focused in
                if focused && allowsSuggestions {
                    browser.beginEditingAddress()
                    updateSuggestions()
                } else {
                    suggestions = []
                    if !focused { allowsSuggestions = false }
                }
            }
            .popover(isPresented: Binding(
                get: { isFocused && !suggestions.isEmpty },
                set: { if !$0 { suggestions = [] } }
            ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                suggestionList
            }
            .help("Type an absolute path or a path beginning with ~, then press Return")
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, url in
                Button {
                    browser.navigate(to: url)
                    isFocused = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(index == selectedSuggestion ? Color.accentColor.opacity(0.14) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 480)
        .padding(.vertical, 5)
    }

    private func updateSuggestions() {
        guard isFocused else {
            suggestions = []
            return
        }
        let expanded = NSString(string: browser.addressText).expandingTildeInPath
        let entered = URL(fileURLWithPath: expanded)
        let endsWithSlash = expanded.hasSuffix("/")
        let directory = endsWithSlash ? entered : entered.deletingLastPathComponent()
        let prefix = endsWithSlash ? "" : entered.lastPathComponent
        let recentMatches = browser.recentLocations.filter {
            $0.path.localizedCaseInsensitiveContains(browser.addressText)
        }

        guard directory.isFileURL,
              let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            suggestions = Array(recentMatches.prefix(8))
            return
        }

        let directoryMatches = children
            .filter {
                FileItem.load($0)?.isDirectory == true &&
                (prefix.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(prefix))
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            .prefix(8)
            .map { $0 }
        let additionalRecentMatches = recentMatches.filter {
            !directoryMatches.contains($0) &&
            $0.path.localizedCaseInsensitiveContains(browser.addressText)
        }
        suggestions = Array((directoryMatches + additionalRecentMatches).prefix(8))
        selectedSuggestion = 0
    }
}
