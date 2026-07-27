import Foundation

@MainActor
final class SpotlightSearchService {
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var continuation: CheckedContinuation<[URL], Never>?

    func search(name: String, in root: URL) async -> [URL] {
        cancel()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let query = NSMetadataQuery()
            query.searchScopes = [root]
            query.predicate = NSPredicate(
                format: "%K CONTAINS[cd] %@",
                NSMetadataItemFSNameKey,
                name
            )
            query.sortDescriptors = [
                NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)
            ]
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let query = self.query else { return }
                    query.disableUpdates()
                    let urls = query.results.compactMap { result -> URL? in
                        guard let item = result as? NSMetadataItem,
                              let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                            return nil
                        }
                        return URL(fileURLWithPath: path)
                    }
                    self.finish(urls)
                }
            }
            self.query = query
            if !query.start() { finish([]) }
        }
    }

    func cancel() {
        query?.stop()
        finish([])
    }

    private func finish(_ urls: [URL]) {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        query = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: urls)
    }
}
