import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var operations: FileOperationManager
    @State private var newFileName = "Untitled.txt"
    @State private var newFolderName = "untitled folder"
    @State private var batchRenamePattern = "{name}-{index}"

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                TabBarView()
                Divider()
                AddressBarRow()
                Divider()
                SearchBarView()
                Divider()
                FileListView()
            }
        }
        .toolbar { toolbar }
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
        .alert("Batch Rename", isPresented: $browser.showsBatchRenamePrompt) {
            TextField("Pattern", text: $batchRenamePattern)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { browser.batchRename(pattern: batchRenamePattern) }
        } message: {
            Text("Use {name} for the original name and {index} for numbering.")
        }
        .alert("NuFinder", isPresented: Binding(
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: browser.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!browser.canGoBack)
            .help("Back")
            Menu {
                if browser.backHistory.isEmpty {
                    Text("No Back History")
                } else {
                    ForEach(browser.backHistory, id: \.self) { url in
                        Button(url.path) { browser.navigateToHistory(url) }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button(action: browser.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!browser.canGoForward)
            .help("Forward")
            Menu {
                if browser.forwardHistory.isEmpty {
                    Text("No Forward History")
                } else {
                    ForEach(browser.forwardHistory, id: \.self) { url in
                        Button(url.path) { browser.navigateToHistory(url) }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button(action: browser.goUp) {
                Image(systemName: "arrow.up")
            }
            .help("Parent Folder")
        }
        ToolbarItemGroup {
            SortMenu()
            Button {
                TerminalService.open(at: browser.currentURL)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open in Terminal")
            Button {
                operations.showsDetails = true
            } label: {
                Image(systemName: "arrow.left.arrow.right.circle")
            }
            .help("File Operations")
        }
    }
}
