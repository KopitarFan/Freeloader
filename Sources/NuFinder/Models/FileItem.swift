import AppKit
import Foundation

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?
    let created: Date?
    let kind: String

    var id: URL { url }

    static func load(_ url: URL) -> FileItem? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .localizedTypeDescriptionKey, .isHiddenKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return FileItem(
            url: url,
            name: url.lastPathComponent,
            isDirectory: values.isDirectory ?? false,
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate,
            created: values.creationDate,
            kind: values.localizedTypeDescription ?? (values.isDirectory == true ? "Folder" : "File")
        )
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum SortField: String, CaseIterable, Identifiable, Codable {
    case name = "Name"
    case kind = "Kind"
    case size = "Size"
    case modified = "Date Modified"
    case created = "Date Created"

    var id: Self { self }
}

struct SortCriterion: Identifiable, Equatable {
    let id = UUID()
    var field: SortField
    var ascending: Bool
}

enum SearchMatchMode: String, CaseIterable, Identifiable, Sendable {
    case contains = "Contains"
    case glob = "Glob"
    case regex = "Regular Expression"
    var id: Self { self }
}

enum FileViewMode: String, CaseIterable, Identifiable, Sendable {
    case list = "List"
    case compact = "Compact"
    case icons = "Icons"
    var id: Self { self }
}

enum SearchKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Items"
    case files = "Files"
    case folders = "Folders"
    var id: Self { self }
}
