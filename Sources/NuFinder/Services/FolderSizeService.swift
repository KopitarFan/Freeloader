import Foundation

@MainActor
final class FolderSizeService: ObservableObject {
    static let shared = FolderSizeService()

    struct Entry {
        let bytes: Int64
        let modified: Date?
    }

    @Published private(set) var entries: [URL: Entry] = [:]
    @Published private(set) var calculating: Set<URL> = []

    private init() {}

    func size(for item: FileItem) -> Int64? {
        guard let entry = entries[item.url], entry.modified == item.modified else { return nil }
        return entry.bytes
    }

    func calculate(_ item: FileItem) {
        guard item.isDirectory, size(for: item) == nil, !calculating.contains(item.url) else { return }
        calculating.insert(item.url)
        let url = item.url
        let modified = item.modified
        Task {
            let bytes = await Task.detached(priority: .utility) {
                FileOperationManager.totalBytes(of: [url])
            }.value
            entries[url] = Entry(bytes: bytes, modified: modified)
            calculating.remove(url)
        }
    }

    func invalidate(_ url: URL) {
        entries[url] = nil
    }
}
