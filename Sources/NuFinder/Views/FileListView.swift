import AppKit
import SwiftUI

struct FileListView: View {
    @EnvironmentObject private var browser: BrowserModel
    @State private var activatingURL: URL?
    @State private var springOpenTask: Task<Void, Never>?
    @State private var typeSelectionBuffer = ""
    @State private var typeSelectionResetTask: Task<Void, Never>?
    @State private var tileFrames: [URL: CGRect] = [:]
    @State private var marqueeRect: CGRect?
    @State private var marqueeBaseSelection: Set<URL> = []
    @State private var isMarqueeSelecting = false
    @State private var marqueeAddsToSelection = false

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Group {
            if browser.viewMode == .list {
                listView
            } else {
                tileView
            }
        }
        .onKeyPress { press in
            guard press.modifiers.isEmpty,
                  press.characters.count == 1,
                  let character = press.characters.first,
                  character.isLetter || character.isNumber else {
                return .ignored
            }
            typeSelectionBuffer.append(character.lowercased())
            if let match = browser.displayedItems.first(where: {
                $0.name.lowercased().hasPrefix(typeSelectionBuffer)
            }) {
                browser.select(match.url)
            }
            typeSelectionResetTask?.cancel()
            typeSelectionResetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                typeSelectionBuffer = ""
            }
            return .handled
        }
        .onChange(of: browser.selection) { _, _ in
            browser.requestAddressBlur()
        }
    }

    private var listView: some View {
        Table(browser.displayedItems, selection: $browser.selection) {
            TableColumn("Name") { item in
                HStack(spacing: 8) {
                    FileThumbnailView(item: item, size: 22)
                    if browser.renameTarget == item.url {
                        RenameField(item: item)
                    } else {
                        Text(item.name).lineLimit(1)
                    }
                    if browser.selection.contains(item.url) && isCut(item.url) {
                        Image(systemName: "scissors")
                            .foregroundStyle(.secondary)
                    }
                    GitStatusBadge(url: item.url)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selectionColor(for: item.url))
                }
                .scaleEffect(activatingURL == item.url ? 0.985 : 1)
                .animation(.easeOut(duration: 0.1), value: activatingURL)
                .contentShape(Rectangle())
                .draggable(dragPayload(for: item.url)) {
                    Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .dropDestination(for: FileDragPayload.self) { payloads, _ in
                    guard item.isDirectory else { return false }
                    moveDroppedItems(payloads.flatMap(\.urls), to: item.url)
                    return true
                } isTargeted: { targeted in
                    if targeted && item.isDirectory {
                        browser.selection = [item.url]
                    }
                    scheduleSpringOpen(item, targeted: targeted)
                }
                .onTapGesture(count: 1) {
                    select(item.url)
                }
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        activate(item)
                    }
                )
                .contextMenu { contextMenu(for: item) }
            }
            .width(min: 220, ideal: 360)

            if browser.showsKindColumn {
                TableColumn("Kind") { item in
                    Text(item.kind)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu { contextMenu(for: item) }
                }
                .width(min: 90, ideal: 130)
            }

            if browser.showsSizeColumn {
                TableColumn("Size") { item in
                    Group {
                        if item.isDirectory {
                            FolderSizeText(item: item)
                        } else {
                            Text(Self.byteFormatter.string(fromByteCount: item.size))
                        }
                    }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                        .contextMenu { contextMenu(for: item) }
                }
                .width(min: 70, ideal: 90)
            }

            if browser.showsModifiedColumn {
                TableColumn("Date Modified") { item in
                    if let modified = item.modified {
                        Text(modified, format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { contextMenu(for: item) }
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu { contextMenu(for: item) }
                    }
                }
                .width(min: 140, ideal: 170)
            }
        }
        .onKeyPress(.return) {
            guard let selectedURL = browser.selection.first,
                  browser.displayedItems.contains(where: { $0.url == selectedURL }) else {
                return .ignored
            }
            browser.renameTarget = selectedURL
            return .handled
        }
        .onKeyPress(.space) {
            guard !browser.selection.isEmpty else { return .ignored }
            QuickLookService.shared.show(Array(browser.selection))
            return .handled
        }
        .contextMenu {
            Button("New Folder…") { browser.showsNewFolderPrompt = true }
            Button("New File…") { browser.requestNewFile() }
            Menu("New from Template") {
                ForEach(TemplateService.templates) { template in
                    Button(template.name) { browser.createFile(from: template) }
                }
            }
            Divider()
            Button("Open in Terminal") { TerminalService.open(at: browser.currentURL) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([browser.currentURL])
            }
            Button("Copy Folder Path") {
                FileActionService.copyPaths([browser.currentURL])
            }
            Divider()
            Button("Paste") {
                // The menu action uses the same real move/copy pipeline as ⌘V.
                Task {
                    await browser.paste(into: browser.currentURL, operations: operationManager)
                }
            }
            .disabled(!browser.canPaste)
            Menu("Paste As") {
                Button("Alias") { browser.pasteAsLinks(into: browser.currentURL, symbolic: false) }
                Button("Symbolic Link") { browser.pasteAsLinks(into: browser.currentURL, symbolic: true) }
            }
            .disabled(!browser.canPaste)
            Divider()
            Button(browser.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                browser.toggleHiddenFiles()
            }
            if !browser.showsHiddenFiles {
                Button("Reveal Hidden Files for 30 Seconds") {
                    browser.showHiddenFilesTemporarily()
                }
            }
            Menu("View As") {
                ForEach(FileViewMode.allCases) { mode in
                    Button {
                        browser.viewMode = mode
                    } label: {
                        if browser.viewMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            }
            Button("Reload") { browser.reload() }
        }
        .dropDestination(for: FileDragPayload.self) { payloads, _ in
            moveDroppedItems(payloads.flatMap(\.urls), to: browser.currentURL)
            return true
        }
        .overlay {
            if browser.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            } else if browser.displayedItems.isEmpty {
                ContentUnavailableView(
                    browser.searchText.isEmpty ? "Empty Folder" : "No Matches",
                    systemImage: browser.searchText.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(browser.searchText.isEmpty
                                      ? "Right-click to create a new file."
                                      : "Try a different name or search mode.")
                )
            }
        }
    }

    private var tileView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: browser.viewMode == .icons ? 105 : 220),
                    spacing: 8
                )],
                spacing: 8
            ) {
                ForEach(browser.displayedItems) { item in
                    tile(for: item)
                }
            }
            .padding(10)
        }
        .coordinateSpace(name: "fileTilePane")
        .onPreferenceChange(TileFramePreferenceKey.self) { tileFrames = $0 }
        .simultaneousGesture(blankAreaTapGesture)
        .simultaneousGesture(marqueeSelectionGesture)
        .overlay(alignment: .topLeading) {
            if let marqueeRect {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.12))
                    .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
                    .frame(width: marqueeRect.width, height: marqueeRect.height)
                    .offset(x: marqueeRect.minX, y: marqueeRect.minY)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: FileDragPayload.self) { payloads, _ in
            moveDroppedItems(payloads.flatMap(\.urls), to: browser.currentURL)
            return true
        }
        .contextMenu {
            Button("New Folder…") { browser.showsNewFolderPrompt = true }
            Button("New File…") { browser.requestNewFile() }
            Menu("New from Template") {
                ForEach(TemplateService.templates) { template in
                    Button(template.name) { browser.createFile(from: template) }
                }
            }
            Divider()
            Button("Open in Terminal") { TerminalService.open(at: browser.currentURL) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([browser.currentURL])
            }
            Button("Copy Folder Path") { FileActionService.copyPaths([browser.currentURL]) }
            Divider()
            Button("Paste") {
                Task {
                    await browser.paste(into: browser.currentURL, operations: operationManager)
                }
            }
            .disabled(!browser.canPaste)
            Menu("Paste As") {
                Button("Alias") { browser.pasteAsLinks(into: browser.currentURL, symbolic: false) }
                Button("Symbolic Link") { browser.pasteAsLinks(into: browser.currentURL, symbolic: true) }
            }
            .disabled(!browser.canPaste)
            Divider()
            Button(browser.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                browser.toggleHiddenFiles()
            }
            if !browser.showsHiddenFiles {
                Button("Reveal Hidden Files for 30 Seconds") {
                    browser.showHiddenFilesTemporarily()
                }
            }
            Button("Reload") { browser.reload() }
        }
        .onMoveCommand { direction in
            moveKeyboardSelection(direction)
        }
        .onKeyPress(.return) {
            guard let url = browser.selection.first,
                  browser.displayedItems.contains(where: { $0.url == url }) else {
                return .ignored
            }
            browser.renameTarget = url
            return .handled
        }
        .overlay {
            if browser.isLoading {
                ProgressView()
            } else if browser.displayedItems.isEmpty {
                ContentUnavailableView(
                    browser.searchText.isEmpty ? "Empty Folder" : "No Matches",
                    systemImage: browser.searchText.isEmpty ? "folder" : "magnifyingglass"
                )
            }
        }
    }

    private func tile(for item: FileItem) -> some View {
        tileLabel(for: item)
            .padding(7)
            .background(selectionColor(for: item.url), in: RoundedRectangle(cornerRadius: 7))
            .modifier(TileFrameReporter(url: item.url))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.name), \(item.kind)")
            .accessibilityAddTraits(browser.selection.contains(item.url) ? .isSelected : [])
            .onTapGesture { select(item.url) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { activate(item) })
            .draggable(dragPayload(for: item.url))
            .dropDestination(for: FileDragPayload.self) { payloads, _ in
                guard item.isDirectory else { return false }
                moveDroppedItems(payloads.flatMap(\.urls), to: item.url)
                return true
            } isTargeted: { targeted in
                scheduleSpringOpen(item, targeted: targeted)
            }
            .contextMenu { contextMenu(for: item) }
    }

    @ViewBuilder
    private func tileLabel(for item: FileItem) -> some View {
        if browser.viewMode == .icons {
            VStack(spacing: 7) {
                FileThumbnailView(item: item, size: 56)
                if browser.renameTarget == item.url {
                    RenameField(item: item)
                        .multilineTextAlignment(.center)
                } else {
                    Text(item.name)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                GitStatusBadge(url: item.url)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
        } else {
            HStack(spacing: 8) {
                FileThumbnailView(item: item, size: 24)
                if browser.renameTarget == item.url {
                    RenameField(item: item)
                } else {
                    Text(item.name).lineLimit(1)
                }
                GitStatusBadge(url: item.url)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @EnvironmentObject private var operationManager: FileOperationManager

    private func isCut(_ url: URL) -> Bool {
        browser.cutItems.contains(url)
    }

    private func selectionColor(for url: URL) -> Color {
        if activatingURL == url {
            return Color.accentColor.opacity(0.42)
        }
        if browser.selection.contains(url) {
            return Color.accentColor.opacity(0.22)
        }
        return .clear
    }

    private func select(_ url: URL) {
        browser.requestAddressBlur()
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        browser.select(
            url,
            command: modifiers.contains(.command),
            shift: modifiers.contains(.shift)
        )
    }

    private var marqueeSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("fileTilePane"))
            .onChanged { value in
                if !isMarqueeSelecting {
                    // A drag that begins on a file belongs to that file's existing
                    // drag-and-drop gesture. Marquee selection starts in empty space.
                    guard !tileFrames.values.contains(where: {
                        $0.insetBy(dx: -2, dy: -2).contains(value.startLocation)
                    }) else {
                        return
                    }
                    isMarqueeSelecting = true
                    browser.requestAddressBlur()
                    browser.beginMarqueeSelection()
                    marqueeBaseSelection = browser.selection
                    marqueeAddsToSelection =
                        NSApp.currentEvent?.modifierFlags.contains(.command) == true
                }

                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                marqueeRect = rect
                let enclosed = Set(tileFrames.compactMap { url, frame in
                    frame.intersects(rect) ? url : nil
                })
                browser.selection = marqueeAddsToSelection
                    ? marqueeBaseSelection.union(enclosed)
                    : enclosed
            }
            .onEnded { _ in
                marqueeRect = nil
                marqueeBaseSelection.removeAll()
                isMarqueeSelecting = false
                marqueeAddsToSelection = false
                browser.endMarqueeSelection()
            }
    }

    private var blankAreaTapGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .named("fileTilePane"))
            .onEnded { value in
                guard NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]).isEmpty != false,
                      !tileFrames.values.contains(where: {
                          $0.insetBy(dx: -2, dy: -2).contains(value.location)
                      }) else {
                    return
                }
                browser.clearSelection()
                browser.requestAddressBlur()
            }
    }

    private func activate(_ item: FileItem) {
        guard activatingURL == nil else { return }
        browser.selection = [item.url]
        activatingURL = item.url
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(130))
            browser.open(item)
            activatingURL = nil
        }
    }

    private func scheduleSpringOpen(_ item: FileItem, targeted: Bool) {
        springOpenTask?.cancel()
        guard targeted, item.isDirectory else { return }
        springOpenTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            browser.navigate(to: item.url)
        }
    }

    private func moveDroppedItems(_ urls: [URL], to destination: URL) {
        let shouldMove = NSApp.currentEvent?.modifierFlags.contains(.option) != true
        let movable = urls.filter {
            (!shouldMove || $0.standardizedFileURL.deletingLastPathComponent() != destination.standardizedFileURL) &&
            $0.standardizedFileURL != destination.standardizedFileURL
        }
        guard !movable.isEmpty else { return }
        Task {
            await browser.transfer(
                sources: movable,
                destination: destination,
                move: shouldMove,
                operations: operationManager
            )
        }
    }

    private func dragPayload(for url: URL) -> FileDragPayload {
        let urls = browser.selection.contains(url) && browser.selection.count > 1
            ? browser.displayedItems.map(\.url).filter(browser.selection.contains)
            : [url]
        return FileDragPayload(urls: urls)
    }

    private func moveKeyboardSelection(_ direction: MoveCommandDirection) {
        let items = browser.displayedItems
        guard !items.isEmpty else { return }
        let current = browser.selection.first.flatMap { url in
            items.firstIndex { $0.url == url }
        } ?? 0
        let columnEstimate = browser.viewMode == .icons ? 6 : 3
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up: delta = -columnEstimate
        case .down: delta = columnEstimate
        @unknown default: delta = 0
        }
        let next = min(max(0, current + delta), items.count - 1)
        browser.select(items[next].url)
    }

    @ViewBuilder
    private func contextMenu(for item: FileItem) -> some View {
        Button("Open") { browser.open(item) }
        if item.isDirectory {
            Button("Open in New Tab") { browser.newTab(at: item.url) }
            Button("Open in New Window") { WindowService.open(at: item.url) }
            if item.isPackage {
                Button("Show Package Contents") { browser.navigate(to: item.url) }
            }
        }
        Button("Quick Look") {
            QuickLookService.shared.show(browser.selection.isEmpty ? [item.url] : Array(browser.selection))
        }
        Button("Get Info") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            browser.showInfoForSelection()
        }
        Button("Reveal in Finder") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            browser.revealSelectionInFinder()
        }
        Menu("Open With") {
            ForEach(FileActionService.openWithApplications(for: item.url), id: \.self) { application in
                Button(application.deletingPathExtension().lastPathComponent) {
                    NSWorkspace.shared.open(
                        [item.url],
                        withApplicationAt: application,
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
            }
            Divider()
            Menu("Always Open With") {
                ForEach(FileActionService.openWithApplications(for: item.url), id: \.self) { application in
                    Button(application.deletingPathExtension().lastPathComponent) {
                        Task {
                            do {
                                try await FileActionService.setDefaultApplication(application, for: item.url)
                            } catch {
                                browser.errorMessage = "Couldn’t change the default app: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
        ShareLink(items: browser.selection.isEmpty ? [item.url] : Array(browser.selection))
        if item.isDirectory {
            Button("Open in Terminal") { TerminalService.open(at: item.url) }
        } else {
            Button("Open Parent in Terminal") {
                TerminalService.open(at: item.url.deletingLastPathComponent())
            }
        }
        Divider()
        Button("Cut") {
            browser.selection.insert(item.url)
            browser.cutSelection()
        }
        Button("Copy") {
            browser.selection.insert(item.url)
            browser.copySelection()
        }
        Button("Duplicate") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            Task { await browser.duplicateSelection(using: operationManager) }
        }
        Button("Compress to ZIP") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            browser.createArchiveFromSelection()
        }
        if ArchiveService.isArchive(item.url) {
            Button("Extract Here") {
                browser.selection = [item.url]
                browser.extractSelectedArchives()
            }
        }
        Button("Copy Path") {
            FileActionService.copyPaths(browser.selection.isEmpty ? [item.url] : Array(browser.selection))
        }
        Button("Copy Filename") {
            FileActionService.copyNames(browser.selection.isEmpty ? [item.url] : Array(browser.selection))
        }
        Button("Copy File URL") {
            FileActionService.copyPaths(
                browser.selection.isEmpty ? [item.url] : Array(browser.selection),
                asFileURLs: true
            )
        }
        Button("Calculate Size") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            browser.calculateSelectedSizes()
        }
        Menu("Calculate Checksums") {
            ForEach(ChecksumAlgorithm.allCases) { algorithm in
                Button(algorithm.rawValue) {
                    if !browser.selection.contains(item.url) { browser.selection = [item.url] }
                    browser.calculateChecksums(algorithms: [algorithm])
                }
            }
            Divider()
            Button("All Checksums") {
                if !browser.selection.contains(item.url) { browser.selection = [item.url] }
                browser.calculateChecksums(algorithms: ChecksumAlgorithm.allCases)
            }
        }
        Button("Batch Rename…") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            browser.showsBatchRenamePrompt = true
        }
        Button("Create Symbolic Link") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            browser.createSymbolicLinks()
        }
        Button("Create Alias") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            browser.createAliases()
        }
        Button("Tags…") {
            if !browser.selection.contains(item.url) { browser.selection = [item.url] }
            browser.tagText = ""
            browser.showsTagPrompt = true
        }
        if browser.selection.count == 2 && browser.selection.allSatisfy({
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }) {
            Button("Compare Files") {
                do { try FileActionService.compare(Array(browser.selection)) }
                catch { browser.errorMessage = "Couldn’t open the comparison tool: \(error.localizedDescription)" }
            }
        }
        Button("Rename") {
            browser.selection = [item.url]
            browser.renameTarget = item.url
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            if !browser.selection.contains(item.url) {
                browser.selection = [item.url]
            }
            browser.moveSelectionToTrash()
        }
        Divider()
        Button("New Folder…") { browser.showsNewFolderPrompt = true }
        Button("New File…") { browser.requestNewFile() }
        Menu("New from Template") {
            ForEach(TemplateService.templates) { template in
                Button(template.name) { browser.createFile(from: template) }
            }
        }
    }
}

private struct TileFramePreferenceKey: PreferenceKey {
    static let defaultValue: [URL: CGRect] = [:]

    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct TileFrameReporter: ViewModifier {
    let url: URL

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TileFramePreferenceKey.self,
                    value: [url: geometry.frame(in: .named("fileTilePane"))]
                )
            }
        }
    }
}

private struct RenameField: View {
    @EnvironmentObject private var browser: BrowserModel
    let item: FileItem
    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $name)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear {
                name = item.name
                focused = true
            }
            .onSubmit { browser.rename(item.url, to: name) }
            .onExitCommand { browser.renameTarget = nil }
    }
}
