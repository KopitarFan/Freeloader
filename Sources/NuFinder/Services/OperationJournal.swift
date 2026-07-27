import Foundation

struct JournalEntry: Codable, Identifiable {
    let id: UUID
    let sourcePath: String
    let targetPath: String
    let isMove: Bool
    let createdAt: Date
}

final class OperationJournal: @unchecked Sendable {
    static let shared = OperationJournal()
    private let lock = NSLock()
    private let fileURL: URL
    private var entries: [JournalEntry] = []

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NuFinder", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("operation-journal.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded
        }
        recoverInterruptedOperations()
    }

    func begin(source: URL, target: URL, move: Bool) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let entry = JournalEntry(
            id: UUID(),
            sourcePath: source.path,
            targetPath: target.path,
            isMove: move,
            createdAt: Date()
        )
        entries.append(entry)
        persist()
        return entry.id
    }

    func complete(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.id == id }
        persist()
    }

    private func recoverInterruptedOperations() {
        for entry in entries {
            let sourceExists = FileManager.default.fileExists(atPath: entry.sourcePath)
            let targetExists = FileManager.default.fileExists(atPath: entry.targetPath)
            if sourceExists && targetExists {
                // The source of a copy, or a failed move fallback, survived.
                // Remove the ambiguous target so restart never leaves a silent
                // partial duplicate.
                try? FileManager.default.removeItem(atPath: entry.targetPath)
            }
            // targetExists && !sourceExists means a move completed before the
            // process exited; preserve it. All other states require no cleanup.
        }
        entries.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
