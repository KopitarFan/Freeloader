import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // A SwiftPM executable reaches didFinishLaunching before SwiftUI has
        // necessarily installed its WindowGroup. Activate on the next run-loop
        // turn so `swift run Freeloader` reliably comes in front of Terminal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.isVisible,
              let url = window.representedURL,
              url.isFileURL else { return }
        WindowService.recordClosedWindow(at: url)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

@main
struct FreeloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var browser = BrowserModel()
    @StateObject private var operations = FileOperationManager()
    @StateObject private var paneFocus = PaneFocusCoordinator()
    @AppStorage("shortcut.commandPalette") private var commandPaletteKey = "p"
    @AppStorage("shortcut.terminal") private var terminalKey = "t"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browser)
                .environmentObject(operations)
                .environmentObject(paneFocus)
                .frame(minWidth: 820, minHeight: 480)
                .onOpenURL { browser.handleDeepLink($0) }
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { browser.undoLastAction() }
                    .keyboardShortcut("z")
                    .disabled(!browser.canUndo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    if !sendTextCommand(#selector(NSText.cut(_:))) {
                        browser.cutSelection()
                    }
                }
                    .keyboardShortcut("x")
                Button("Copy") {
                    if !sendTextCommand(#selector(NSText.copy(_:))) {
                        browser.copySelection()
                    }
                }
                    .keyboardShortcut("c")
                Button("Paste") {
                    if !sendTextCommand(#selector(NSText.paste(_:))) {
                        Task { await browser.paste(into: browser.currentURL, operations: operations) }
                    }
                }
                .keyboardShortcut("v")
                Divider()
                Button("Select All") {
                    if activeBrowser.isEditingAddress || activeBrowser.renameTarget != nil {
                        if sendTextCommand(#selector(NSText.selectAll(_:))) {
                            return
                        }
                    }
                    activeBrowser.selectAll()
                }
                    .keyboardShortcut("a")
                Button("Invert Selection") { browser.invertSelection() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Find Files…") { activeBrowser.requestSearchFocus() }
                    .keyboardShortcut("f")
                Button("Clear Search") {
                    activeBrowser.searchText = ""
                    activeBrowser.updateSearch()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(activeBrowser.searchText.isEmpty)
            }
            CommandGroup(after: .newItem) {
                Button("New Window") { WindowService.open(at: browser.currentURL) }
                    .keyboardShortcut("n")
                Button("New Tab") { browser.newTab() }
                    .keyboardShortcut("t")
                Button("Close Tab") {
                    if browser.tabs.count > 1 {
                        browser.closeTab(browser.activeTabID)
                    } else {
                        NSApp.keyWindow?.close()
                    }
                }
                .keyboardShortcut("w")
                Button("Reopen Closed Tab") { browser.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(!browser.canReopenClosedTab)
                Button("Reopen Closed Window") { WindowService.reopenLastClosedWindow() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!WindowService.canReopenClosedWindow)
                Button("Go to Folder…") { browser.requestAddressFocus() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Connect to Server…") { browser.requestConnectToServer() }
                    .keyboardShortcut("k")
                Divider()
                Button("New File") { browser.requestNewFile() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Folder") { browser.showsNewFolderPrompt = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open in Terminal") { TerminalService.open(at: browser.currentURL) }
                    .keyboardShortcut(shortcutKey(terminalKey, fallback: "t"), modifiers: [.command, .option])
                Button("Duplicate") {
                    Task { await browser.duplicateSelection(using: operations) }
                }
                .keyboardShortcut("d")
                .disabled(browser.selection.isEmpty)
                Button("Get Info") { browser.showInfoForSelection() }
                    .keyboardShortcut("i")
                    .disabled(browser.selection.isEmpty)
                Button("Quick Look") { QuickLookService.shared.show(Array(browser.selection)) }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(browser.selection.isEmpty)
                Button("Batch Rename") { browser.showsBatchRenamePrompt = true }
                    .disabled(browser.selection.isEmpty)
                Button("Copy Path") { FileActionService.copyPaths(Array(browser.selection)) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(browser.selection.isEmpty)
                Divider()
                Button("Move to Trash") { browser.moveSelectionToTrash() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(browser.selection.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Toggle("Folder Tree in Sidebar", isOn: $browser.showsTree)
                Picker("View Mode", selection: $browser.viewMode) {
                    ForEach(FileViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Menu("Columns") {
                    Toggle("Kind", isOn: $browser.showsKindColumn)
                    Toggle("Size", isOn: $browser.showsSizeColumn)
                    Toggle("Date Modified", isOn: $browser.showsModifiedColumn)
                }
                Button(browser.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    browser.toggleHiddenFiles()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                Button("Reload") { browser.reload() }
                    .keyboardShortcut("r")
            }
            CommandMenu("Go") {
                Menu("Recent Locations") {
                    ForEach(browser.recentLocations, id: \.self) { url in
                        Button(url.path) { browser.navigate(to: url) }
                    }
                }
                Button("Back") { browser.goBack() }
                    .keyboardShortcut("[")
                    .disabled(!browser.canGoBack)
                Button("Forward") { browser.goForward() }
                    .keyboardShortcut("]")
                    .disabled(!browser.canGoForward)
                Button("Enclosing Folder") { browser.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
            }
            CommandMenu("Commands") {
                Button("Command Palette…") { browser.showsCommandPalette = true }
                    .keyboardShortcut(shortcutKey(commandPaletteKey, fallback: "p"), modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsView()
        }
    }

    private func shortcutKey(_ value: String, fallback: Character) -> KeyEquivalent {
        KeyEquivalent(value.first ?? fallback)
    }

    private var activeBrowser: BrowserModel {
        paneFocus.activeBrowser ?? browser
    }

    @MainActor
    private func sendTextCommand(_ selector: Selector) -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
              editor.isFieldEditor,
              editor.delegate is NSTextField else {
            return false
        }
        return NSApp.sendAction(selector, to: nil, from: nil)
    }
}
