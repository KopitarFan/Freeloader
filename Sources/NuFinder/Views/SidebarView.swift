import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var operations: FileOperationManager
    @State private var springOpenTask: Task<Void, Never>?
    @State private var volumes: [MountedVolume] = []
    @State private var pendingEject: MountedVolume?

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
                Section("Locations") {
                    ForEach(volumes) { volume in
                        HStack(spacing: 8) {
                            Button {
                                browser.navigate(to: volume.url)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(volume.name, systemImage: volume.isRemovable ? "externaldrive" : "internaldrive")
                                        .lineLimit(1)
                                    if let fraction = volume.usedFraction {
                                        ProgressView(value: fraction)
                                            .controlSize(.mini)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 2)
                            if volume.isEjectable {
                                Button {
                                    requestEject(volume)
                                } label: {
                                    Image(systemName: "eject")
                                }
                                .buttonStyle(.borderless)
                                .help("Eject \(volume.name)")
                            }
                        }
                        .dropDestination(for: URL.self) { urls, _ in
                            moveDroppedItems(urls, to: volume.url)
                        }
                    }
                }
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
        .task {
            refreshVolumes()
        }
        .confirmationDialog(
            "Transfers are still running",
            isPresented: Binding(
                get: { pendingEject != nil },
                set: { if !$0 { pendingEject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eject Anyway", role: .destructive) {
                if let volume = pendingEject { eject(volume) }
                pendingEject = nil
            }
            Button("Cancel", role: .cancel) { pendingEject = nil }
        } message: {
            Text("Ejecting now may interrupt a file operation using this drive.")
        }
    }

    private func refreshVolumes() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]
        volumes = (FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return MountedVolume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                isRemovable: values.volumeIsRemovable ?? false,
                isEjectable: values.volumeIsEjectable ?? false,
                totalBytes: values.volumeTotalCapacity.map(Int64.init),
                availableBytes: values.volumeAvailableCapacityForImportantUsage
            )
        }
    }

    private func requestEject(_ volume: MountedVolume) {
        if operations.operations.contains(where: { $0.finishedAt == nil }) {
            pendingEject = volume
        } else {
            eject(volume)
        }
    }

    private func eject(_ volume: MountedVolume) {
        Task {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
                refreshVolumes()
            } catch {
                browser.errorMessage = "Couldn’t eject \(volume.name): \(error.localizedDescription)"
            }
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

private struct MountedVolume: Identifiable {
    let url: URL
    let name: String
    let isRemovable: Bool
    let isEjectable: Bool
    let totalBytes: Int64?
    let availableBytes: Int64?

    var id: URL { url }

    var usedFraction: Double? {
        guard let totalBytes, let availableBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(totalBytes - availableBytes) / Double(totalBytes)))
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
