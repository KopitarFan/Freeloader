import AppKit
import Foundation
import SwiftUI

struct BrowserTab: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var history: [URL]
    var historyIndex: Int
    var isPinned = false

    var title: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}

private struct FolderViewPreference: Codable {
    var viewMode: String
    var showsKind: Bool
    var showsSize: Bool
    var showsModified: Bool
    var sortFields: [String]
    var sortAscending: [Bool]
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var currentURL: URL
    @Published var items: [FileItem] = []
    @Published var selection: Set<URL> = []
    @Published var addressText = ""
    @Published var errorMessage: String?
    @Published var showsTree = false
    @Published var showsNewFilePrompt = false
    @Published var showsNewFolderPrompt = false
    @Published var showsHiddenFiles = false
    @Published var itemForInfo: FileItem?
    @Published var renameTarget: URL?
    @Published var sortCriteria = [SortCriterion(field: .name, ascending: true)]
    @Published private(set) var cutItems: Set<URL> = []
    @Published private(set) var customFavorites: [URL] = []
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var activeTabID: UUID
    @Published private(set) var recentLocations: [URL] = []
    @Published var addressFocusToken = UUID()
    @Published private(set) var isLoading = false
    @Published var searchText = ""
    @Published var searchSubfolders = false
    @Published var searchMatchMode: SearchMatchMode = .contains
    @Published var searchKindFilter: SearchKindFilter = .all
    @Published var minimumSearchSizeMB = 0
    @Published var modifiedWithinDays = 0
    @Published var usesSpotlight = true
    @Published private(set) var searchResults: [FileItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var savedSearches: [String] = []
    @Published var viewMode: FileViewMode = .list
    @Published var showsKindColumn = true
    @Published var showsSizeColumn = true
    @Published var showsModifiedColumn = true
    @Published var showsBatchRenamePrompt = false
    @Published var showsTagPrompt = false
    @Published var showsCommandPalette = false
    @Published var tagText = ""
    @Published var detailTitle: String?
    @Published var detailText = ""

    private var history: [URL] = []
    private var historyIndex = -1
    private var clipboard: [URL] = []
    private var clipboardIsCut = false
    private let watcher = DirectoryWatcher()
    private var undoActions: [() -> Void] = []
    private let persistsSession: Bool
    private var closedTabs: [BrowserTab] = []
    private var reloadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var selectionAnchor: URL?
    private let spotlight = SpotlightSearchService()

    var canUndo: Bool { !undoActions.isEmpty }
    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    init(initialURL: URL? = nil, restoresSession: Bool = true) {
        persistsSession = restoresSession
        let home = FileManager.default.homeDirectoryForCurrentUser
        let restored = restoresSession ? UserDefaults.standard.stringArray(forKey: "openTabPaths")?
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) } ?? [] : []
        let initialURLs = initialURL.map { [$0] } ?? (restored.isEmpty ? [home] : restored)
        let pinnedPaths = Set(UserDefaults.standard.stringArray(forKey: "pinnedTabPaths") ?? [])
        let initialTabs = initialURLs.map {
            BrowserTab(
                id: UUID(),
                url: $0,
                history: [$0],
                historyIndex: 0,
                isPinned: pinnedPaths.contains($0.path)
            )
        }
        let restoredActiveIndex = restoresSession
            ? min(UserDefaults.standard.integer(forKey: "activeTabIndex"), initialTabs.count - 1)
            : 0
        tabs = initialTabs
        activeTabID = initialTabs[restoredActiveIndex].id
        currentURL = initialTabs[restoredActiveIndex].url
        history = initialTabs[restoredActiveIndex].history
        historyIndex = initialTabs[restoredActiveIndex].historyIndex
        recentLocations = UserDefaults.standard.stringArray(forKey: "recentLocationPaths")?
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) } ?? []
        savedSearches = UserDefaults.standard.stringArray(forKey: "savedSearches") ?? []
        customFavorites = UserDefaults.standard.stringArray(forKey: "customFavoritePaths")?
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) } ?? []
        navigate(to: currentURL, addingHistory: false)
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }
    var canPaste: Bool { !clipboard.isEmpty }

    func navigate(to rawURL: URL, addingHistory: Bool = true) {
        let url = rawURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errorMessage = "The folder “\(url.path)” could not be opened."
            return
        }
        currentURL = url
        restoreViewPreferences(for: url)
        addressText = url.path
        selection.removeAll()
        if addingHistory {
            if historyIndex < history.count - 1 { history.removeSubrange((historyIndex + 1)...) }
            if history.last != url { history.append(url) }
            historyIndex = history.count - 1
        }
        recordRecent(url)
        syncActiveTab()
        reload()
        watcher.watch(url) { [weak self] in self?.reload() }
    }

    func navigateFromAddress() {
        let expanded = NSString(string: addressText).expandingTildeInPath
        navigate(to: URL(fileURLWithPath: expanded))
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "nufinder",
              url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value else {
            return
        }
        navigate(to: URL(fileURLWithPath: path))
    }

    func beginEditingAddress() {
        // Keep the canonical path visible and editable whenever the field gains focus.
        addressText = currentURL.path
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        navigate(to: history[historyIndex], addingHistory: false)
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        navigate(to: history[historyIndex], addingHistory: false)
    }

    var backHistory: [URL] {
        guard historyIndex > 0 else { return [] }
        return Array(history[..<historyIndex].reversed())
    }

    var forwardHistory: [URL] {
        guard historyIndex < history.count - 1 else { return [] }
        return Array(history[(historyIndex + 1)...])
    }

    func navigateToHistory(_ url: URL) {
        guard let index = history.firstIndex(of: url) else { return }
        historyIndex = index
        navigate(to: url, addingHistory: false)
    }

    func requestAddressFocus() {
        addressFocusToken = UUID()
    }

    func newTab(at url: URL? = nil) {
        let destination = (url ?? currentURL).standardizedFileURL
        let tab = BrowserTab(id: UUID(), url: destination, history: [destination], historyIndex: 0)
        tabs.append(tab)
        persistTabs()
        selectTab(tab.id)
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard !tabs[index].isPinned else { return }
        let closed = tabs.remove(at: index)
        closedTabs.append(closed)
        if activeTabID == id {
            selectTab(tabs[min(index, tabs.count - 1)].id)
        }
        persistTabs()
    }

    func reopenClosedTab() {
        guard var tab = closedTabs.popLast() else { return }
        tab = BrowserTab(
            id: UUID(),
            url: tab.url,
            history: tab.history,
            historyIndex: tab.historyIndex,
            isPinned: false
        )
        tabs.append(tab)
        selectTab(tab.id)
        persistTabs()
    }

    func duplicateTab(_ id: UUID) {
        guard let source = tabs.first(where: { $0.id == id }) else { return }
        let copy = BrowserTab(
            id: UUID(),
            url: source.url,
            history: source.history,
            historyIndex: source.historyIndex
        )
        tabs.append(copy)
        selectTab(copy.id)
    }

    func togglePinnedTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isPinned.toggle()
        let tab = tabs.remove(at: index)
        let insertionIndex = tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.endIndex
        if tab.isPinned {
            tabs.insert(tab, at: insertionIndex)
        } else {
            tabs.append(tab)
        }
        persistTabs()
    }

    func selectTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        syncActiveTab()
        activeTabID = id
        currentURL = tab.url
        history = tab.history
        historyIndex = tab.historyIndex
        addressText = tab.url.path
        selection.removeAll()
        reload()
        watcher.watch(tab.url) { [weak self] in self?.reload() }
        persistTabs()
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        if parent.path != currentURL.path { navigate(to: parent) }
    }

    func reload() {
        reloadTask?.cancel()
        isLoading = true
        let directory = currentURL
        let includesHidden = showsHiddenFiles
        reloadTask = Task { [weak self] in
            // Coalesce bursts from filesystem notifications and rapid navigation.
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let urls = try FileManager.default.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: [
                            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                            .creationDateKey, .localizedTypeDescriptionKey
                        ],
                        options: includesHidden ? [] : [.skipsHiddenFiles]
                    )
                    return urls.compactMap(FileItem.load)
                }
            }.value

            guard !Task.isCancelled, let self, self.currentURL == directory else { return }
            self.isLoading = false
            switch result {
            case .success(let loadedItems):
                self.items = self.sort(loadedItems)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func sortedAgain() { items = sort(items) }

    var displayedItems: [FileItem] {
        searchText.isEmpty ? items : searchResults
    }

    func updateSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            spotlight.cancel()
            isSearching = false
            searchResults = []
            return
        }
        let root = currentURL
        let recursive = searchSubfolders
        let mode = searchMatchMode
        let kindFilter = searchKindFilter
        let minimumBytes = Int64(minimumSearchSizeMB) * 1_000_000
        let days = modifiedWithinDays
        let visibleItems = items
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let spotlightURLs: [URL]?
            if recursive && self?.usesSpotlight == true && mode == .contains {
                spotlightURLs = await self?.spotlight.search(name: query, in: root)
            } else {
                spotlightURLs = nil
            }
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                let candidates: [FileItem]
                if let spotlightURLs {
                    candidates = spotlightURLs.compactMap(FileItem.load)
                } else if recursive {
                    let keys: [URLResourceKey] = [
                        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                        .creationDateKey, .localizedTypeDescriptionKey
                    ]
                    let enumerator = FileManager.default.enumerator(
                        at: root,
                        includingPropertiesForKeys: keys,
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )
                    var found: [FileItem] = []
                    while let url = enumerator?.nextObject() as? URL {
                        if Task.isCancelled { break }
                        if let item = FileItem.load(url) { found.append(item) }
                    }
                    candidates = found
                } else {
                    candidates = visibleItems
                }
                let cutoff = days > 0
                    ? Calendar.current.date(byAdding: .day, value: -days, to: Date())
                    : nil
                return candidates.filter { item in
                    guard Self.matches(item.name, query: query, mode: mode) else { return false }
                    if kindFilter == .files && item.isDirectory { return false }
                    if kindFilter == .folders && !item.isDirectory { return false }
                    if minimumBytes > 0 && !item.isDirectory && item.size < minimumBytes { return false }
                    if let cutoff, let modified = item.modified, modified < cutoff { return false }
                    return true
                }
            }.value
            guard !Task.isCancelled, let self, self.currentURL == root else { return }
            self.searchResults = self.sort(results)
            self.isSearching = false
        }
    }

    nonisolated static func matches(_ name: String, query: String, mode: SearchMatchMode) -> Bool {
        switch mode {
        case .contains:
            return name.localizedCaseInsensitiveContains(query)
        case .glob:
            let escaped = NSRegularExpression.escapedPattern(for: query)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            return name.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
        case .regex:
            return name.range(of: query, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    func saveCurrentSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !savedSearches.contains(query) else { return }
        savedSearches.insert(query, at: 0)
        UserDefaults.standard.set(savedSearches, forKey: "savedSearches")
    }

    func removeSavedSearch(_ query: String) {
        savedSearches.removeAll { $0 == query }
        UserDefaults.standard.set(savedSearches, forKey: "savedSearches")
    }

    func select(_ url: URL, command: Bool = false, shift: Bool = false) {
        if shift, let anchor = selectionAnchor,
           let start = displayedItems.firstIndex(where: { $0.url == anchor }),
           let end = displayedItems.firstIndex(where: { $0.url == url }) {
            selection.formUnion(displayedItems[min(start, end)...max(start, end)].map(\.url))
        } else if command {
            if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
            selectionAnchor = url
        } else {
            selection = [url]
            selectionAnchor = url
        }
    }

    func selectAll() { selection = Set(displayedItems.map(\.url)) }

    func invertSelection() {
        selection = Set(displayedItems.map(\.url)).subtracting(selection)
    }

    func calculateSelectedSizes() {
        let urls = Array(selection)
        guard !urls.isEmpty else { return }
        detailTitle = "Calculating Size…"
        detailText = ""
        Task {
            let bytes = await Task.detached { FileOperationManager.totalBytes(of: urls) }.value
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            detailTitle = "Selection Size"
            detailText = "\(formatter.string(fromByteCount: bytes)) across \(urls.count) item\(urls.count == 1 ? "" : "s")."
        }
    }

    func calculateChecksums(algorithms: [ChecksumAlgorithm] = [.sha256]) {
        let urls = selection.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        guard !urls.isEmpty else {
            errorMessage = "Select one or more regular files to calculate checksums."
            return
        }
        detailTitle = "Calculating Checksums…"
        detailText = ""
        Task {
            let lines = await Task.detached {
                urls.sorted { $0.path < $1.path }.flatMap { url in
                    algorithms.map { algorithm in
                        do {
                            return "\(algorithm.rawValue)  \(try FileActionService.checksum(of: url, algorithm: algorithm))  \(url.lastPathComponent)"
                        } catch {
                            return "\(algorithm.rawValue)  ERROR  \(url.lastPathComponent): \(error.localizedDescription)"
                        }
                    }
                }
            }.value
            detailTitle = "Checksums"
            detailText = lines.joined(separator: "\n")
        }
    }

    func batchRename(pattern: String) {
        var request = BatchRenameRequest()
        request.pattern = pattern
        batchRename(request)
    }

    func batchRename(_ request: BatchRenameRequest) {
        let sources = displayedItems.filter { selection.contains($0.url) }
        guard !sources.isEmpty else { return }
        let targets: [URL]
        do {
            targets = try sources.enumerated().map { offset, item in
                guard let newName = Self.renamedFilename(
                    for: item,
                    request: request,
                    index: request.startIndex + offset
                ) else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                return item.url.deletingLastPathComponent().appendingPathComponent(newName)
            }
            guard Set(targets).count == targets.count else {
                throw CocoaError(.fileWriteFileExists)
            }
            let sourceSet = Set(sources.map(\.url))
            for target in targets where !sourceSet.contains(target) {
                if FileManager.default.fileExists(atPath: target.path) {
                    throw CocoaError(.fileWriteFileExists)
                }
            }

            let temporary = sources.map {
                $0.url.deletingLastPathComponent()
                    .appendingPathComponent(".freeloader-rename-\(UUID().uuidString)")
            }
            var staged = 0
            var finalized = 0
            do {
                for index in sources.indices {
                    try FileManager.default.moveItem(at: sources[index].url, to: temporary[index])
                    staged += 1
                }
                for index in sources.indices {
                    try FileManager.default.moveItem(at: temporary[index], to: targets[index])
                    finalized += 1
                }
            } catch {
                for index in 0..<finalized where FileManager.default.fileExists(atPath: targets[index].path) {
                    try? FileManager.default.moveItem(at: targets[index], to: sources[index].url)
                }
                for index in 0..<staged where FileManager.default.fileExists(atPath: temporary[index].path) {
                    try? FileManager.default.moveItem(at: temporary[index], to: sources[index].url)
                }
                throw error
            }
            reload()
            selection = Set(targets)
            registerUndo { [weak self] in
                for index in sources.indices.reversed() {
                    try? FileManager.default.moveItem(at: targets[index], to: sources[index].url)
                }
                self?.reload()
            }
        } catch {
            errorMessage = "Batch rename was rolled back: \(error.localizedDescription)"
        }
    }

    nonisolated static func renamedFilename(
        for item: FileItem,
        request: BatchRenameRequest,
        index: Int
    ) -> String? {
        let originalExtension = item.url.pathExtension
        var stem = item.url.deletingPathExtension().lastPathComponent
        if !request.find.isEmpty {
            stem = stem.replacingOccurrences(of: request.find, with: request.replacement)
        }
        switch request.letterCase {
        case .unchanged: break
        case .lowercase: stem = stem.lowercased()
        case .uppercase: stem = stem.uppercased()
        case .title: stem = stem.capitalized
        }
        let chosenExtension = request.extensionOverride
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let ext = chosenExtension.isEmpty ? originalExtension : chosenExtension
        var name = request.pattern
            .replacingOccurrences(of: "{name}", with: stem)
            .replacingOccurrences(of: "{index}", with: String(index))
            .replacingOccurrences(of: "{ext}", with: ext)
        if !ext.isEmpty && (name as NSString).pathExtension.isEmpty {
            name += ".\(ext)"
        }
        guard !name.isEmpty, !name.contains("/") else { return nil }
        return name
    }

    func createSymbolicLinks() {
        let sources = Array(selection)
        guard !sources.isEmpty else { return }
        var links: [URL] = []
        do {
            for source in sources {
                let desired = currentURL.appendingPathComponent("\(source.lastPathComponent) link")
                let link = FileOperationManager.uniqueDestination(for: desired, in: currentURL)
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
                links.append(link)
            }
            reload()
            selection = Set(links)
            registerUndo { [weak self] in
                links.forEach { try? FileManager.default.removeItem(at: $0) }
                self?.reload()
            }
        } catch {
            links.forEach { try? FileManager.default.removeItem(at: $0) }
            errorMessage = error.localizedDescription
        }
    }

    func createAliases() {
        let sources = Array(selection)
        guard !sources.isEmpty else { return }
        var aliases: [URL] = []
        do {
            for source in sources {
                let desired = currentURL.appendingPathComponent("\(source.lastPathComponent) alias")
                let alias = FileOperationManager.uniqueDestination(for: desired, in: currentURL)
                let data = try source.bookmarkData(options: .suitableForBookmarkFile)
                try URL.writeBookmarkData(data, to: alias)
                aliases.append(alias)
            }
            reload()
            selection = Set(aliases)
            registerUndo { [weak self] in
                aliases.forEach { try? FileManager.default.removeItem(at: $0) }
                self?.reload()
            }
        } catch {
            aliases.forEach { try? FileManager.default.removeItem(at: $0) }
            errorMessage = "Couldn’t create the alias: \(error.localizedDescription)"
        }
    }

    func createFile(from template: FileTemplate) {
        let desired = currentURL.appendingPathComponent(template.suggestedFilename)
        let destination = FileOperationManager.uniqueDestination(for: desired, in: currentURL)
        do {
            try template.contents.write(to: destination, options: .atomic)
            reload()
            selection = [destination]
            registerUndo { [weak self] in
                try? FileManager.default.removeItem(at: destination)
                self?.reload()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyTagsFromPrompt() {
        let tags = tagText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            for url in selection {
                try FileActionService.setFinderTags(tags, on: url)
            }
            reload()
        } catch {
            errorMessage = "Couldn’t update tags: \(error.localizedDescription)"
        }
    }

    func showHiddenFilesTemporarily() {
        showsHiddenFiles = true
        reload()
        Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            showsHiddenFiles = false
            reload()
        }
    }

    func createArchiveFromSelection() {
        let sources = displayedItems.filter { selection.contains($0.url) }.map(\.url)
        guard !sources.isEmpty else { return }
        let baseName = sources.count == 1 ? sources[0].deletingPathExtension().lastPathComponent : "Archive"
        let desired = currentURL.appendingPathComponent("\(baseName).zip")
        let destination = FileOperationManager.uniqueDestination(for: desired, in: currentURL)
        detailTitle = "Creating Archive…"
        detailText = ""
        Task {
            do {
                try await Task.detached {
                    try ArchiveService.createZip(from: sources, at: destination)
                }.value
                detailTitle = nil
                reload()
                selection = [destination]
                registerUndo { [weak self] in
                    try? FileManager.default.removeItem(at: destination)
                    self?.reload()
                }
            } catch {
                detailTitle = nil
                errorMessage = "Couldn’t create the archive: \(error.localizedDescription)"
            }
        }
    }

    func extractSelectedArchives() {
        let archives = selection.filter(ArchiveService.isArchive)
        guard !archives.isEmpty else { return }
        detailTitle = "Extracting Archive…"
        detailText = ""
        Task {
            var destinations: [URL] = []
            do {
                for archive in archives {
                    let stem = archive.deletingPathExtension().lastPathComponent
                    let desired = currentURL.appendingPathComponent(stem)
                    let destination = FileOperationManager.uniqueDestination(for: desired, in: currentURL)
                    try await Task.detached {
                        try ArchiveService.extract(archive, to: destination)
                    }.value
                    destinations.append(destination)
                }
                detailTitle = nil
                reload()
                selection = Set(destinations)
                registerUndo { [weak self] in
                    destinations.forEach { try? FileManager.default.removeItem(at: $0) }
                    self?.reload()
                }
            } catch {
                destinations.forEach { try? FileManager.default.removeItem(at: $0) }
                detailTitle = nil
                errorMessage = "Couldn’t extract the archive: \(error.localizedDescription)"
            }
        }
    }

    private func sort(_ input: [FileItem]) -> [FileItem] {
        input.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            for criterion in sortCriteria {
                let order = compare(lhs, rhs, by: criterion.field)
                if order != .orderedSame {
                    return criterion.ascending ? order == .orderedAscending : order == .orderedDescending
                }
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func compare(_ lhs: FileItem, _ rhs: FileItem, by field: SortField) -> ComparisonResult {
        switch field {
        case .name: return lhs.name.localizedStandardCompare(rhs.name)
        case .kind: return lhs.kind.localizedStandardCompare(rhs.kind)
        case .size: return lhs.size == rhs.size ? .orderedSame : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
        case .modified: return compare(lhs.modified, rhs.modified)
        case .created: return compare(lhs.created, rhs.created)
        }
    }

    private func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        guard let lhs, let rhs else {
            if lhs == nil && rhs == nil { return .orderedSame }
            return lhs == nil ? .orderedAscending : .orderedDescending
        }
        return lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }

    func open(_ item: FileItem) {
        if item.isDirectory { navigate(to: item.url) }
        else { NSWorkspace.shared.open(item.url) }
    }

    func cutSelection() {
        clipboard = Array(selection)
        clipboardIsCut = true
        cutItems = selection
    }

    func copySelection() {
        clipboard = Array(selection)
        clipboardIsCut = false
        cutItems.removeAll()
    }

    func paste(into destination: URL, operations: FileOperationManager) async {
        let sources = clipboard
        let move = clipboardIsCut
        guard !sources.isEmpty else { return }
        await transfer(sources: sources, destination: destination, move: move, operations: operations)
        if move {
            clipboard.removeAll()
            clipboardIsCut = false
            cutItems.removeAll()
        }
        reload()
    }

    func pasteAsLinks(into destination: URL, symbolic: Bool) {
        let sources = clipboard
        guard !sources.isEmpty else { return }
        var created: [URL] = []
        do {
            for source in sources {
                if symbolic {
                    let desired = destination.appendingPathComponent(source.lastPathComponent)
                    let link = FileOperationManager.uniqueDestination(for: desired, in: destination)
                    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
                    created.append(link)
                } else {
                    let desired = destination.appendingPathComponent("\(source.lastPathComponent) alias")
                    let alias = FileOperationManager.uniqueDestination(for: desired, in: destination)
                    let data = try source.bookmarkData(options: .suitableForBookmarkFile)
                    try URL.writeBookmarkData(data, to: alias)
                    created.append(alias)
                }
            }
            reload()
            selection = Set(created)
            registerUndo { [weak self] in
                created.forEach { try? FileManager.default.removeItem(at: $0) }
                self?.reload()
            }
        } catch {
            created.forEach { try? FileManager.default.removeItem(at: $0) }
            errorMessage = "Couldn’t paste the link: \(error.localizedDescription)"
        }
    }

    func requestNewFile() { showsNewFilePrompt = true }

    func createFile(named name: String) {
        guard let url = validatedNewItemURL(named: name) else { return }
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            errorMessage = "The file could not be created."
            return
        }
        reload()
        selection = [url]
        registerUndo { [weak self] in
            try? FileManager.default.removeItem(at: url)
            self?.reload()
        }
    }

    func createFolder(named name: String) {
        guard let url = validatedNewItemURL(named: name) else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            reload()
            selection = [url]
            registerUndo { [weak self] in
                try? FileManager.default.removeItem(at: url)
                self?.reload()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ url: URL, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            errorMessage = "Enter a name without a slash."
            return
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard target != url else { renameTarget = nil; return }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            errorMessage = "An item named “\(trimmed)” already exists."
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            renameTarget = nil
            reload()
            selection = [target]
            registerUndo { [weak self] in
                try? FileManager.default.moveItem(at: target, to: url)
                self?.reload()
                self?.selection = [url]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicateSelection(using operations: FileOperationManager) async {
        let sources = Array(selection)
        guard !sources.isEmpty else { return }
        let results = await operations.perform(
            sources: sources,
            destination: currentURL,
            move: false,
            policy: .keepBoth
        )
        reload()
        selection = Set(results.map(\.destination))
        registerUndo { [weak self] in
            results.forEach { try? FileManager.default.removeItem(at: $0.destination) }
            self?.reload()
        }
    }

    func revealSelectionInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(Array(selection))
    }

    func showInfoForSelection() {
        guard let url = selection.first else { return }
        itemForInfo = items.first { $0.url == url } ?? FileItem.load(url)
    }

    func toggleHiddenFiles() {
        showsHiddenFiles.toggle()
        reload()
    }

    func undoLastAction() {
        undoActions.popLast()?()
        objectWillChange.send()
    }

    private func registerUndo(_ action: @escaping () -> Void) {
        undoActions.append(action)
        objectWillChange.send()
    }

    private func validatedNewItemURL(named name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            errorMessage = "Enter a name without a slash."
            return nil
        }
        let url = currentURL.appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "An item named “\(trimmed)” already exists."
            return nil
        }
        return url
    }

    private func syncActiveTab() {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        tabs[index].url = currentURL
        tabs[index].history = history
        tabs[index].historyIndex = historyIndex
        persistTabs()
    }

    private func persistTabs() {
        guard persistsSession else { return }
        UserDefaults.standard.set(tabs.map { $0.url.path }, forKey: "openTabPaths")
        UserDefaults.standard.set(
            tabs.filter(\.isPinned).map { $0.url.path },
            forKey: "pinnedTabPaths"
        )
        UserDefaults.standard.set(
            tabs.firstIndex(where: { $0.id == activeTabID }) ?? 0,
            forKey: "activeTabIndex"
        )
    }

    private func recordRecent(_ url: URL) {
        recentLocations.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentLocations.insert(url, at: 0)
        if recentLocations.count > 15 { recentLocations.removeLast(recentLocations.count - 15) }
        UserDefaults.standard.set(recentLocations.map(\.path), forKey: "recentLocationPaths")
    }

    func saveViewPreferences() {
        let preference = FolderViewPreference(
            viewMode: viewMode.rawValue,
            showsKind: showsKindColumn,
            showsSize: showsSizeColumn,
            showsModified: showsModifiedColumn,
            sortFields: sortCriteria.map { $0.field.rawValue },
            sortAscending: sortCriteria.map(\.ascending)
        )
        guard let data = try? JSONEncoder().encode(preference) else { return }
        UserDefaults.standard.set(data, forKey: viewPreferenceKey(for: currentURL))
    }

    private func restoreViewPreferences(for url: URL) {
        guard let data = UserDefaults.standard.data(forKey: viewPreferenceKey(for: url)),
              let preference = try? JSONDecoder().decode(FolderViewPreference.self, from: data) else {
            return
        }
        viewMode = FileViewMode(rawValue: preference.viewMode) ?? .list
        showsKindColumn = preference.showsKind
        showsSizeColumn = preference.showsSize
        showsModifiedColumn = preference.showsModified
        let restoredSort = zip(preference.sortFields, preference.sortAscending).compactMap { field, ascending in
            SortField.allCases.first { $0.rawValue == field }
                .map { SortCriterion(field: $0, ascending: ascending) }
        }
        if !restoredSort.isEmpty { sortCriteria = restoredSort }
    }

    private func viewPreferenceKey(for url: URL) -> String {
        "folderViewPreference.\(url.standardizedFileURL.path)"
    }

    func moveSelectionToTrash() {
        let urls = Array(selection)
        guard !urls.isEmpty else { return }

        NSWorkspace.shared.recycle(urls) { [weak self] trashedURLs, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = "Couldn’t move the selected item\(urls.count == 1 ? "" : "s") to the Trash: \(error.localizedDescription)"
                    return
                }
                self.selection.subtract(urls)
                self.cutItems.subtract(urls)
                self.reload()
                self.registerUndo { [weak self] in
                    for (original, trashed) in trashedURLs {
                        try? FileManager.default.moveItem(at: trashed, to: original)
                    }
                    self?.reload()
                }
            }
        }
    }

    @discardableResult
    func transfer(
        sources: [URL],
        destination: URL,
        move: Bool,
        operations: FileOperationManager
    ) async -> [FileTransferResult] {
        let results = await operations.perform(sources: sources, destination: destination, move: move)
        reload()
        guard !results.isEmpty else { return [] }
        registerUndo { [weak self] in
            for result in results.reversed() {
                if result.wasMove {
                    try? FileOperationManager.transfer(
                        source: result.destination,
                        target: result.source,
                        move: true
                    )
                } else {
                    try? FileManager.default.removeItem(at: result.destination)
                }
            }
            self?.reload()
        }
        return results
    }

    @discardableResult
    func addFavorite(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errorMessage = "Only folders can be added to Favorites."
            return false
        }

        let builtIn = Set([
            FileManager.default.homeDirectoryForCurrentUser,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        ].map(\.standardizedFileURL))
        guard !builtIn.contains(candidate), !customFavorites.contains(candidate) else { return true }

        customFavorites.append(candidate)
        UserDefaults.standard.set(customFavorites.map(\.path), forKey: "customFavoritePaths")
        return true
    }

    func removeFavorite(_ url: URL) {
        customFavorites.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(customFavorites.map(\.path), forKey: "customFavoritePaths")
    }
}
