import AppKit
import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64
    let modified: Date?
    let created: Date?
    let kind: String

    var id: URL { url }

    static func load(_ url: URL) -> FileItem? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .localizedTypeDescriptionKey, .isHiddenKey,
            .isSymbolicLinkKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isSymbolicLink = values.isSymbolicLink ?? false
        let isDirectory = values.isDirectory == true ||
            (isSymbolicLink && isNavigableDirectory(url.resolvingSymlinksInPath()))
        return FileItem(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate,
            created: values.creationDate,
            kind: values.localizedTypeDescription ?? (isDirectory ? "Folder" : "File")
        )
    }

    static func isNavigableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) &&
            isDirectory.boolValue
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    var isImage: Bool {
        guard !isDirectory,
              let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    var isPackage: Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
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

enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case folder = "This Folder"
    case subfolders = "Subfolders"
    case home = "Home"
    case computer = "This Mac"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .folder: "folder"
        case .subfolders: "folder.badge.gearshape"
        case .home: "house"
        case .computer: "desktopcomputer"
        }
    }
}
