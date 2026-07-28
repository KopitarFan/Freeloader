import Cocoa
import FinderSync

final class FinderSyncExtension: FIFinderSync {
    override init() {
        super.init()
        // Home-folder coverage provides the Finder context menu without
        // requiring a shared App Group container or cross-app-data permission.
        FIFinderSyncController.default().directoryURLs = [
            FileManager.default.homeDirectoryForCurrentUser
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Freeloader")
        let open = NSMenuItem(
            title: "Open in Freeloader",
            action: #selector(openInFreeloader),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)
        return menu
    }

    @objc private func openInFreeloader() {
        guard let url = FIFinderSyncController.default().targetedURL() else { return }
        var components = URLComponents()
        components.scheme = "freeloader"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let deepLink = components.url {
            NSWorkspace.shared.open(deepLink)
        }
    }
}
