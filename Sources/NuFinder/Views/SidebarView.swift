import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var operations: FileOperationManager
    @State private var springOpenTask: Task<Void, Never>?

    private var builtInFavorites: [(String, String, URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("Home", "house", home),
            ("Desktop", "menubar.dock.rectangle", home.appendingPathComponent("Desktop")),
            ("Documents", "doc", home.appendingPathComponent("Documents")),
            ("Downloads", "arrow.down.circle", home.appendingPathComponent("Downloads"))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Favorites") {
                    ForEach(builtInFavorites, id: \.2) { title, icon, url in
                        Button {
                            browser.navigate(to: url)
                        } label: {
                            Label(title, systemImage: icon)
                        }
                        .buttonStyle(.plain)
                        .dropDestination(for: URL.self) { urls, _ in
                            moveDroppedItems(urls, to: url)
                        } isTargeted: { targeted in
                            scheduleSpringOpen(url, targeted: targeted)
                        }
                    }
                    ForEach(browser.customFavorites, id: \.self) { url in
                        Button {
                            browser.navigate(to: url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "folder")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .dropDestination(for: URL.self) { urls, _ in
                            moveDroppedItems(urls, to: url)
                        } isTargeted: { targeted in
                            scheduleSpringOpen(url, targeted: targeted)
                        }
                        .contextMenu {
                            Button("Remove from Favorites", role: .destructive) {
                                browser.removeFavorite(url)
                            }
                        }
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    urls.reduce(false) { added, url in
                        browser.addFavorite(url) || added
                    }
                } isTargeted: { _ in }
                if browser.showsTree {
                    Section("Folders") {
                        FolderTreeNode(url: FileManager.default.homeDirectoryForCurrentUser)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            Toggle(isOn: $browser.showsTree) {
                Label("Folder Tree", systemImage: "list.bullet.indent")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moveDroppedItems(_ urls: [URL], to destination: URL) -> Bool {
        let shouldMove = NSApp.currentEvent?.modifierFlags.contains(.option) != true
        let movable = urls.filter {
            (!shouldMove || $0.standardizedFileURL.deletingLastPathComponent() != destination.standardizedFileURL) &&
            $0.standardizedFileURL != destination.standardizedFileURL
        }
        guard !movable.isEmpty else { return false }
        Task {
            await browser.transfer(
                sources: movable,
                destination: destination,
                move: shouldMove,
                operations: operations
            )
        }
        return true
    }

    private func scheduleSpringOpen(_ url: URL, targeted: Bool) {
        springOpenTask?.cancel()
        guard targeted else { return }
        springOpenTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            browser.navigate(to: url)
        }
    }
}

private struct FolderTreeNode: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var operations: FileOperationManager
    let url: URL
    @State private var expanded = false
    @State private var children: [URL] = []
    @State private var springExpandTask: Task<Void, Never>?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(children, id: \.self) { child in
                FolderTreeNode(url: child)
            }
        } label: {
            Button {
                browser.navigate(to: url)
            } label: {
                Label(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                      systemImage: "folder")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .dropDestination(for: URL.self) { urls, _ in
                moveDroppedItems(urls)
            } isTargeted: { targeted in
                springExpandTask?.cancel()
                guard targeted, !expanded else { return }
                springExpandTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    expanded = true
                    if children.isEmpty { loadChildren() }
                }
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && children.isEmpty { loadChildren() }
        }
    }

    private func loadChildren() {
        children = ((try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func moveDroppedItems(_ urls: [URL]) -> Bool {
        let destination = url.standardizedFileURL
        let shouldMove = NSApp.currentEvent?.modifierFlags.contains(.option) != true
        let movable = urls.filter {
            (!shouldMove || $0.standardizedFileURL.deletingLastPathComponent() != destination) &&
            $0.standardizedFileURL != destination
        }
        guard !movable.isEmpty else { return false }
        Task {
            await browser.transfer(
                sources: movable,
                destination: destination,
                move: shouldMove,
                operations: operations
            )
            loadChildren()
        }
        return true
    }
}
