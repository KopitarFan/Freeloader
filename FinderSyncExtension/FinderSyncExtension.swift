import Cocoa
import FinderSync

final class FinderSyncExtension: FIFinderSync {
    override init() {
        super.init()
        // The host app writes intentionally monitored roots here in a future
        // app-group-enabled distribution profile. Keep the initial extension
        // scoped to the user's home folder rather than claiming every volume.
        let paths = UserDefaults(suiteName: "group.com.miguelrodriguez.NuFinder")?
            .stringArray(forKey: "finderSyncMonitoredPaths") ?? []
        let configured = paths.map { URL(fileURLWithPath: $0) }
        FIFinderSyncController.default().directoryURLs = Set(
            configured.isEmpty
                ? [FileManager.default.homeDirectoryForCurrentUser]
                : configured
        )
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "NuFinder")
        let open = NSMenuItem(
            title: "Open in NuFinder",
            action: #selector(openInNuFinder),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)
        return menu
    }

    @objc private func openInNuFinder() {
        guard let url = FIFinderSyncController.default().targetedURL() else { return }
        var components = URLComponents()
        components.scheme = "nufinder"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let deepLink = components.url {
            NSWorkspace.shared.open(deepLink)
        }
    }
}
