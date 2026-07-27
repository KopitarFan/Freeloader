import Foundation

enum FinderSyncBridge {
    static let appGroup = "group.com.miguelrodriguez.NuFinder"
    private static let monitoredPathsKey = "finderSyncMonitoredPaths"

    static func updateMonitoredFolders(_ urls: [URL]) {
        UserDefaults(suiteName: appGroup)?.set(
            urls.map { $0.standardizedFileURL.path },
            forKey: monitoredPathsKey
        )
    }
}
