import Foundation

enum GitFileState: String, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case conflicted = "!"
    case untracked = "?"
    case ignored = "I"
}

@MainActor
final class GitStatusService: ObservableObject {
    static let shared = GitStatusService()

    @Published private(set) var states: [URL: GitFileState] = [:]
    @Published private(set) var repositoryRoot: URL?

    private var refreshTask: Task<Void, Never>?

    private init() {}

    func state(for url: URL) -> GitFileState? {
        states[url.standardizedFileURL]
    }

    func refresh(for folder: URL) {
        refreshTask?.cancel()
        refreshTask = Task {
            let result = await Task.detached(priority: .utility) {
                Self.loadStatuses(in: folder)
            }.value
            guard !Task.isCancelled else { return }
            repositoryRoot = result.root
            states = result.states
        }
    }

    private nonisolated static func loadStatuses(in folder: URL) -> (root: URL?, states: [URL: GitFileState]) {
        guard let rootPath = try? runGit(["-C", folder.path, "rev-parse", "--show-toplevel"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return (nil, [:])
        }
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL
        guard let output = try? runGit([
            "-C", root.path, "status", "--porcelain=v1", "-z",
            "--untracked-files=all", "--ignored=matching"
        ]) else {
            return (root, [:])
        }

        var states: [URL: GitFileState] = [:]
        let records = output.split(separator: "\0", omittingEmptySubsequences: true)
        var skipRenameTarget = false
        for recordSlice in records {
            if skipRenameTarget {
                skipRenameTarget = false
                continue
            }
            let record = String(recordSlice)
            guard record.count >= 4 else { continue }
            let status = String(record.prefix(2))
            let path = String(record.dropFirst(3))
            let state: GitFileState
            if status == "??" { state = .untracked }
            else if status == "!!" { state = .ignored }
            else if status.contains("U") || status == "AA" || status == "DD" { state = .conflicted }
            else if status.contains("R") { state = .renamed; skipRenameTarget = true }
            else if status.contains("D") { state = .deleted }
            else if status.contains("A") { state = .added }
            else { state = .modified }
            states[root.appendingPathComponent(path).standardizedFileURL] = state
        }
        return (root, states)
    }

    private nonisolated static func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
