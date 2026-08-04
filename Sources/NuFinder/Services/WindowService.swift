import AppKit
import SwiftUI

@MainActor
enum WindowService {
    private static let closedWindowsKey = "recentlyClosedWindowPaths"

    static func open(at url: URL) {
        let browser = BrowserModel(initialURL: url, restoresSession: false)
        let operations = FileOperationManager()
        let paneFocus = PaneFocusCoordinator()
        let root = ContentView()
            .environmentObject(browser)
            .environmentObject(operations)
            .environmentObject(paneFocus)
            .frame(minWidth: 820, minHeight: 480)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        let splitPane = UserDefaults.standard.bool(forKey: "showsSplitPane")
        window.setContentSize(NSSize(width: splitPane ? 1180 : 1040, height: 680))
        window.title = "Freeloader"
        window.representedURL = url
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    static var canReopenClosedWindow: Bool {
        !closedWindowPaths.isEmpty
    }

    static func recordClosedWindow(at url: URL) {
        var paths = closedWindowPaths
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(10)), forKey: closedWindowsKey)
    }

    static func reopenLastClosedWindow() {
        var paths = closedWindowPaths
        guard !paths.isEmpty else { return }
        let path = paths.removeFirst()
        UserDefaults.standard.set(paths, forKey: closedWindowsKey)
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            reopenLastClosedWindow()
            return
        }
        open(at: url)
    }

    private static var closedWindowPaths: [String] {
        UserDefaults.standard.stringArray(forKey: closedWindowsKey) ?? []
    }
}
