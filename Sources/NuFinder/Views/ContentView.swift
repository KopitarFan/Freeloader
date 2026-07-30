import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var operations: FileOperationManager
    @StateObject private var secondaryBrowser = BrowserModel(
        initialURL: FileManager.default.homeDirectoryForCurrentUser,
        restoresSession: false
    )
    @AppStorage("showsSplitPane") private var showsSplitPane = false
    @AppStorage("toolbar.showsSplit") private var toolbarShowsSplit = true
    @AppStorage("toolbar.showsTerminal") private var toolbarShowsTerminal = true
    @AppStorage("toolbar.showsOperations") private var toolbarShowsOperations = true
    @AppStorage("gitStatusEnabled") private var gitStatusEnabled = false
    @State private var newFileName = "Untitled.txt"
    @State private var newFolderName = "untitled folder"

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            HStack(spacing: 0) {
                browserPane(for: browser)
                if showsSplitPane {
                    Divider()
                    browserPane(for: secondaryBrowser)
                        .frame(minWidth: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showsSplitPane)
        }
        .toolbar { toolbar }
        .onAppear { NSApp.keyWindow?.representedURL = browser.currentURL }
        .onChange(of: browser.currentURL) { _, url in
            NSApp.keyWindow?.representedURL = url
        }
        .onChange(of: browser.viewMode) { _, _ in browser.saveViewPreferences() }
        .onChange(of: browser.showsKindColumn) { _, _ in browser.saveViewPreferences() }
        .onChange(of: browser.showsSizeColumn) { _, _ in browser.saveViewPreferences() }
        .onChange(of: browser.showsModifiedColumn) { _, _ in browser.saveViewPreferences() }
        .onChange(of: browser.sortCriteria) { _, _ in browser.saveViewPreferences() }
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
        .sheet(isPresented: Binding(
            get: { browser.detailTitle != nil },
            set: { if !$0 { browser.detailTitle = nil } }
        )) {
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
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: previewItem(in: model)?.url)
        }
        .environmentObject(model)
        .environmentObject(operations)
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
              !item.isDirectory else {
            return nil
        }
        return item
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                ForEach(browser.backHistory.reversed(), id: \.self) { url in
                    Button(url.path) { browser.navigateToHistory(url) }
                }
            } label: {
                FreeloaderToolbarIcon(systemName: "chevron.left")
            } primaryAction: {
                browser.goBack()
            }
            .disabled(!browser.canGoBack)
            .help("Back; open the menu for history")

            Menu {
                ForEach(browser.forwardHistory.reversed(), id: \.self) { url in
                    Button(url.path) { browser.navigateToHistory(url) }
                }
            } label: {
                FreeloaderToolbarIcon(systemName: "chevron.right")
            } primaryAction: {
                browser.goForward()
            }
            .disabled(!browser.canGoForward)
            .help("Forward; open the menu for history")

            Button(action: browser.goUp) {
                FreeloaderToolbarIcon(systemName: "arrow.up")
            }
            .buttonStyle(.plain)
            .help("Parent Folder")
        }
        ToolbarItemGroup {
            Menu {
                ForEach(FileViewMode.allCases) { mode in
                    Button {
                        browser.viewMode = mode
                    } label: {
                        Label(
                            mode.rawValue,
                            systemImage: browser.viewMode == mode
                                ? "checkmark"
                                : viewModeIcon(mode)
                        )
                    }
                }
            } label: {
                FreeloaderToolbarIcon(
                    systemName: viewModeIcon(browser.viewMode),
                    isActive: browser.viewMode != .list
                )
            }
            .help("View Mode: \(browser.viewMode.rawValue)")

            SortMenu()
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
                    TerminalService.open(at: browser.currentURL)
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

    private func viewModeIcon(_ mode: FileViewMode) -> String {
        switch mode {
        case .list: "list.bullet"
        case .compact: "rectangle.grid.1x2"
        case .icons: "square.grid.2x2"
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
