import AppKit
import SwiftUI

@MainActor
enum WindowService {
    static func open(at url: URL) {
        let browser = BrowserModel(initialURL: url, restoresSession: false)
        let operations = FileOperationManager()
        let root = ContentView()
            .environmentObject(browser)
            .environmentObject(operations)
            .frame(minWidth: 820, minHeight: 480)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 1040, height: 680))
        window.title = "NuFinder"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
