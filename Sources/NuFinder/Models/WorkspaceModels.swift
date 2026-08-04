import Foundation

struct BrowserPaneSnapshot: Codable, Equatable {
    var tabPaths: [String]
    var pinnedTabPaths: [String]
    var activeTabIndex: Int
    var viewMode: String
    var showsKind: Bool
    var showsSize: Bool
    var showsModified: Bool
    var sortFields: [String]
    var sortAscending: [Bool]
}

struct SavedWorkspace: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var primary: BrowserPaneSnapshot
    var secondary: BrowserPaneSnapshot
    var splitPane: Bool
    var showsTree: Bool
    var updatedAt: Date
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [SavedWorkspace] = []
    @Published var launchWorkspaceID: UUID? {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private static let workspacesKey = "savedWorkspaces"
    private static let launchKey = "launchWorkspaceID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.workspacesKey),
           let decoded = try? JSONDecoder().decode([SavedWorkspace].self, from: data) {
            workspaces = decoded
        }
        launchWorkspaceID = defaults.string(forKey: Self.launchKey).flatMap(UUID.init(uuidString:))
    }

    var launchWorkspace: SavedWorkspace? {
        launchWorkspaceID.flatMap { id in workspaces.first { $0.id == id } }
    }

    func save(_ workspace: SavedWorkspace) {
        if let index = workspaces.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(workspace.name) == .orderedSame }) {
            var replacement = workspace
            replacement.id = workspaces[index].id
            workspaces[index] = replacement
        } else {
            workspaces.append(workspace)
        }
        workspaces.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persist()
    }

    func rename(_ workspace: SavedWorkspace, to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspaces[index].name = trimmed
        workspaces[index].updatedAt = Date()
        workspaces.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persist()
    }

    func remove(_ workspace: SavedWorkspace) {
        workspaces.removeAll { $0.id == workspace.id }
        if launchWorkspaceID == workspace.id { launchWorkspaceID = nil }
        persist()
    }

    func toggleLaunch(_ workspace: SavedWorkspace) {
        launchWorkspaceID = launchWorkspaceID == workspace.id ? nil : workspace.id
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) {
            defaults.set(data, forKey: Self.workspacesKey)
        }
        defaults.set(launchWorkspaceID?.uuidString, forKey: Self.launchKey)
    }
}
