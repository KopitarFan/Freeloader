import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var operations: FileOperationManager
    @EnvironmentObject private var paneFocus: PaneFocusCoordinator
    @StateObject private var secondaryBrowser = BrowserModel(
        initialURL: FileManager.default.homeDirectoryForCurrentUser,
        restoresSession: false
    )
    @StateObject private var workspaceStore = WorkspaceStore()
    @AppStorage("showsSplitPane") private var showsSplitPane = false
    @AppStorage("toolbar.showsSplit") private var toolbarShowsSplit = true
    @AppStorage("toolbar.showsTerminal") private var toolbarShowsTerminal = true
    @AppStorage("toolbar.showsOperations") private var toolbarShowsOperations = true
    @AppStorage("gitStatusEnabled") private var gitStatusEnabled = false
    @State private var newFileName = "Untitled.txt"
    @State private var newFolderName = "untitled folder"
    @State private var workspaceName = ""
    @State private var showsSaveWorkspace = false
    @State private var showsWorkspaceManager = false
    @State private var didRestoreLaunchWorkspace = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if showsSplitPane {
                GeometryReader { geometry in
                    let paneWidth = max(0, (geometry.size.width - 1) / 2)
                    HStack(spacing: 0) {
                        browserPane(for: browser)
                            .frame(width: paneWidth)
                            .clipped()
                    Divider()
                    browserPane(for: secondaryBrowser)
                            .frame(width: paneWidth)
                            .clipped()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .transition(.opacity)
            } else {
                browserPane(for: browser)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsSplitPane)
        .background {
            WindowLayoutSizingView(
                minimumContentSize: showsSplitPane
                    ? CGSize(width: 1180, height: 560)
                    : CGSize(width: 820, height: 480)
            )
        }
        .toolbar { toolbar }
        .onAppear {
            paneFocus.activate(browser)
            NSApp.keyWindow?.representedURL = browser.currentURL
            if !didRestoreLaunchWorkspace {
                didRestoreLaunchWorkspace = true
                if let workspace = workspaceStore.launchWorkspace {
                    restore(workspace)
                }
            }
        }
        .onChange(of: browser.currentURL) { _, url in
            NSApp.keyWindow?.representedURL = url
        }
        .alert("New File", isPresented: $browser.showsNewFilePrompt) {
            TextField("File name", text: $newFileName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                browser.createFile(named: newFileName)
                newFileName = "Untitled.txt"
            }
        } message: {
            Text("Create an empty file in \(browser.currentURL.lastPathComponent).")
        }
        .alert("New Folder", isPresented: $browser.showsNewFolderPrompt) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                browser.createFolder(named: newFolderName)
                newFolderName = "untitled folder"
            }
        } message: {
            Text("Create a folder in \(browser.currentURL.lastPathComponent).")
        }
        .alert("Save Workspace", isPresented: $showsSaveWorkspace) {
            TextField("Workspace name", text: $workspaceName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveWorkspace() }
                .disabled(workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Save both panes, open tabs, view modes, and sorting.")
        }
        .sheet(isPresented: $showsWorkspaceManager) {
            WorkspaceManagerView(store: workspaceStore, openWorkspace: restore)
        }
        .sheet(isPresented: $browser.showsBatchRenamePrompt) {
            BatchRenameView()
                .environmentObject(browser)
        }
        .sheet(isPresented: $browser.showsConnectToServer) {
            ConnectToServerView()
                .environmentObject(browser)
        }
        .sheet(isPresented: $browser.showsCommandPalette) {
            CommandPaletteView()
                .environmentObject(browser)
                .environmentObject(operations)
        }
        .alert("Tags", isPresented: $browser.showsTagPrompt) {
            TextField("work, important, red", text: $browser.tagText)
            Button("Cancel", role: .cancel) {}
            Button("Apply") { browser.applyTagsFromPrompt() }
        } message: {
            Text("Enter comma-separated Finder tags. Leave the field empty to remove tags.")
        }
        .alert("Freeloader", isPresented: Binding(
            get: { browser.errorMessage != nil },
            set: { if !$0 { browser.errorMessage = nil } }
        )) {
            Button("OK") { browser.errorMessage = nil }
        } message: {
            Text(browser.errorMessage ?? "")
        }
        .sheet(isPresented: $operations.showsDetails) {
            TransferDetailsView()
                .environmentObject(operations)
        }
        .sheet(item: $browser.itemForInfo) { item in
            FileInfoView(item: item)
                .environmentObject(browser)
        }
        .sheet(isPresented: detailPresented) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(browser.detailTitle ?? "Details").font(.title2.bold())
                    Spacer()
                    Button("Done") { browser.detailTitle = nil }
                        .keyboardShortcut(.defaultAction)
                }
                if browser.detailText.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(browser.detailText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 560, minHeight: 300)
        }
    }

    @ViewBuilder
    private func browserPane(for model: BrowserModel) -> some View {
        VStack(spacing: 0) {
            TabBarView()
            Divider()
            AddressBarRow()
            Divider()
            SearchBarView()
            Divider()
            HStack(spacing: 0) {
                FileListView()
                if let previewItem = previewItem(in: model) {
                    Divider()
                    ImagePreviewPane(item: previewItem)
                        .simultaneousGesture(
                            TapGesture().onEnded { model.clearSelection() }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: previewItem(in: model)?.url)
        }
        .background {
            PaneInteractionMonitor {
                paneFocus.activate(model)
                NSApp.keyWindow?.representedURL = model.currentURL
            }
        }
        .clipped()
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(
                        showsSplitPane && paneFocus.isActive(model) ? 0.85 : 0
                    ),
                    lineWidth: 2
                )
                .padding(1)
                .allowsHitTesting(false)
        }
        .environmentObject(model)
        .environmentObject(operations)
        .onChange(of: model.viewMode) { _, _ in model.saveViewPreferences() }
        .onChange(of: model.showsKindColumn) { _, _ in model.saveViewPreferences() }
        .onChange(of: model.showsSizeColumn) { _, _ in model.saveViewPreferences() }
        .onChange(of: model.showsModifiedColumn) { _, _ in model.saveViewPreferences() }
        .onChange(of: model.sortCriteria) { _, _ in model.saveViewPreferences() }
        .sheet(isPresented: Binding(
            get: { model.showsGallery },
            set: { model.showsGallery = $0 }
        )) {
            GalleryView()
                .environmentObject(model)
        }
        .task(id: model.currentURL) {
            if gitStatusEnabled {
                GitStatusService.shared.refresh(for: model.currentURL)
            }
        }
    }

    private func previewItem(in model: BrowserModel) -> FileItem? {
        let selectedURL = model.selection.count == 1 ? model.selection.first : nil
        let previewURL = model.isMarqueeSelecting
            ? model.marqueePreviewURL
            : selectedURL
        guard let url = previewURL,
              let item = model.displayedItems.first(where: { $0.url == url }),
              !item.isDirectory,
              !isArchive(item.url) else {
            return nil
        }
        return item
    }

    private func isArchive(_ url: URL) -> Bool {
        if ArchiveService.isArchive(url) { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .archive)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                if workspaceStore.workspaces.isEmpty {
                    Text("No Saved Workspaces")
                } else {
                    ForEach(workspaceStore.workspaces) { workspace in
                        Button(workspace.name) { restore(workspace) }
                    }
                    Divider()
                }
                Button("Save Current Workspace…") {
                    workspaceName = ""
                    showsSaveWorkspace = true
                }
                Button("Manage Workspaces…") { showsWorkspaceManager = true }
            } label: {
                FreeloaderToolbarIcon(systemName: "square.stack.3d.up")
            }
            .menuStyle(.borderlessButton)
            .help("Workspaces")
            if toolbarShowsSplit {
                Button {
                    showsSplitPane.toggle()
                } label: {
                    FreeloaderToolbarIcon(
                        systemName: "rectangle.split.2x1",
                        isActive: showsSplitPane
                    )
                }
                .buttonStyle(.plain)
                .help(showsSplitPane ? "Close Split Pane" : "Open Split Pane")
            }
            if toolbarShowsTerminal {
                Button {
                    TerminalService.open(at: activeBrowser.currentURL)
                } label: {
                    FreeloaderToolbarIcon(systemName: "terminal")
                }
                .buttonStyle(.plain)
                .help("Open in Terminal")
            }
            if toolbarShowsOperations {
                Button {
                    operations.showsDetails = true
                } label: {
                    FreeloaderToolbarIcon(
                        systemName: "arrow.left.arrow.right.circle",
                        badge: operations.operations.filter { $0.finishedAt == nil }.count
                    )
                }
                .buttonStyle(.plain)
                .help("File Operations")
            }
        }
    }

    private var detailPresented: Binding<Bool> {
        Binding(
            get: { browser.detailTitle != nil },
            set: { isPresented in
                if !isPresented { browser.detailTitle = nil }
            }
        )
    }

    private var activeBrowser: BrowserModel {
        paneFocus.activeBrowser ?? browser
    }

    private func saveWorkspace() {
        let name = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        workspaceStore.save(SavedWorkspace(
            id: UUID(),
            name: name,
            primary: browser.workspaceSnapshot(),
            secondary: secondaryBrowser.workspaceSnapshot(),
            splitPane: showsSplitPane,
            showsTree: browser.showsTree,
            updatedAt: Date()
        ))
    }

    private func restore(_ workspace: SavedWorkspace) {
        showsSplitPane = workspace.splitPane
        browser.showsTree = workspace.showsTree
        browser.restoreWorkspace(workspace.primary)
        secondaryBrowser.restoreWorkspace(workspace.secondary)
        paneFocus.activate(browser)
    }

}

private struct WorkspaceManagerView: View {
    @ObservedObject var store: WorkspaceStore
    let openWorkspace: (SavedWorkspace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var workspaceToRename: SavedWorkspace?
    @State private var renamedWorkspace = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workspaces").font(.title2.bold())
                    Text("Return to a complete Freeloader layout in one click.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if store.workspaces.isEmpty {
                ContentUnavailableView(
                    "No Saved Workspaces",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Use the workspace toolbar menu to save your current layout.")
                )
            } else {
                List(store.workspaces) { workspace in
                    HStack(spacing: 12) {
                        Image(systemName: workspace.splitPane ? "rectangle.split.2x1" : "rectangle")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.name).fontWeight(.medium)
                            Text(workspace.updatedAt, style: .date)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.toggleLaunch(workspace)
                        } label: {
                            Image(systemName: store.launchWorkspaceID == workspace.id ? "play.circle.fill" : "play.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(store.launchWorkspaceID == workspace.id ? "Don’t Open at Launch" : "Open at Launch")
                        Button("Open") {
                            openWorkspace(workspace)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .contextMenu {
                        Button("Rename…") {
                            workspaceToRename = workspace
                            renamedWorkspace = workspace.name
                        }
                        Button("Delete", role: .destructive) { store.remove(workspace) }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 360)
        .alert("Rename Workspace", isPresented: Binding(
            get: { workspaceToRename != nil },
            set: { if !$0 { workspaceToRename = nil } }
        )) {
            TextField("Workspace name", text: $renamedWorkspace)
            Button("Cancel", role: .cancel) { workspaceToRename = nil }
            Button("Rename") {
                if let workspaceToRename { store.rename(workspaceToRename, to: renamedWorkspace) }
                workspaceToRename = nil
            }
        }
    }
}

private struct ConnectToServerView: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect to Server")
                        .font(.title2.bold())
                    Text("Mount an SMB share using macOS authentication.")
                        .foregroundStyle(.secondary)
                }
            }

            TextField("smb://server/share", text: $browser.serverAddress)
                .textFieldStyle(.roundedBorder)
                .focused($addressFocused)
                .onSubmit { connect() }

            if !browser.recentServers.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Recent Servers")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(browser.recentServers, id: \.self) { address in
                        Button {
                            browser.serverAddress = address
                        } label: {
                            Label(address, systemImage: "clock")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                if browser.isConnectingToServer {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    browser.showsConnectToServer = false
                }
                .disabled(browser.isConnectingToServer)
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(browser.isConnectingToServer)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear { addressFocused = true }
        .interactiveDismissDisabled(browser.isConnectingToServer)
    }

    private func connect() {
        Task { await browser.connectToServer() }
    }
}

struct FreeloaderToolbarIcon: View {
    let systemName: String
    var isActive = false
    var badge = 0

    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .symbolEffect(.bounce, value: isActive)
            .foregroundStyle(.white)
            .frame(width: 29, height: 25)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isActive
                                ? [Color(red: 0.60, green: 0.28, blue: 0.67),
                                   Color(red: 0.35, green: 0.13, blue: 0.41)]
                                : [Color(red: 0.50, green: 0.22, blue: 0.56),
                                   Color(red: 0.26, green: 0.09, blue: 0.31)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 0.7)
                    }
                    .shadow(
                        color: Color(red: 0.26, green: 0.09, blue: 0.31).opacity(isHovering ? 0.38 : 0.22),
                        radius: isHovering ? 5 : 2,
                        y: isHovering ? 2 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text(badge > 9 ? "9+" : "\(badge)")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.26, green: 0.09, blue: 0.31))
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12, minHeight: 12)
                        .background(.white, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .scaleEffect(isHovering ? 1.06 : 1)
            .rotationEffect(.degrees(isHovering ? -1.5 : 0))
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: isHovering)
            .onHover { isHovering = $0 }
    }
}
