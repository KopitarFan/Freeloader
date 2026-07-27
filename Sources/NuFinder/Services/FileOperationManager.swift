import Foundation

enum ConflictPolicy: String, CaseIterable, Identifiable {
    case keepBoth = "Keep Both"
    case replace = "Replace"
    case skip = "Skip"
    var id: Self { self }
}

struct FileTransferResult: Sendable {
    let source: URL
    let destination: URL
    let wasMove: Bool
}

struct FileOperation: Identifiable, Sendable {
    let id: UUID
    let sourceNames: [String]
    let destination: URL
    let isMove: Bool
    var completedBytes: Int64
    var totalBytes: Int64
    var currentItem: String
    var startedAt: Date
    var finishedAt: Date?
    var error: String?
    var isPaused = false
    var isCancelled = false

    var progress: Double {
        totalBytes == 0 ? (finishedAt == nil ? 0 : 1) : min(1, Double(completedBytes) / Double(totalBytes))
    }

    var bytesPerSecond: Double {
        let elapsed = max(0.01, (finishedAt ?? Date()).timeIntervalSince(startedAt))
        return Double(completedBytes) / elapsed
    }
}

@MainActor
final class FileOperationManager: ObservableObject, @unchecked Sendable {
    @Published var operations: [FileOperation] = []
    @Published var showsDetails = false
    @Published var conflictPolicy: ConflictPolicy = .keepBoth

    private var cancelled: Set<UUID> = []
    private var paused: Set<UUID> = []
    private var controls: [UUID: TransferControl] = [:]

    @discardableResult
    func perform(
        sources: [URL],
        destination: URL,
        move: Bool,
        policy overridePolicy: ConflictPolicy? = nil
    ) async -> [FileTransferResult] {
        let id = UUID()
        let total = await Task.detached { Self.totalBytes(of: sources) }.value
        operations.insert(FileOperation(
            id: id,
            sourceNames: sources.map(\.lastPathComponent),
            destination: destination,
            isMove: move,
            completedBytes: 0,
            totalBytes: total,
            currentItem: sources.first?.lastPathComponent ?? "",
            startedAt: Date()
        ), at: 0)
        showsDetails = true
        let control = TransferControl()
        controls[id] = control
        var results: [FileTransferResult] = []

        do {
            for source in sources {
                while paused.contains(id) && !cancelled.contains(id) {
                    try await Task.sleep(for: .milliseconds(150))
                }
                if cancelled.contains(id) { break }
                try Self.validate(source: source, destination: destination, move: move)
                if move && source.standardizedFileURL.deletingLastPathComponent() == destination.standardizedFileURL {
                    continue
                }

                update(id) { $0.currentItem = source.lastPathComponent }
                let resolution = try resolveTarget(
                    for: source,
                    in: destination,
                    policy: overridePolicy ?? conflictPolicy
                )
                guard let target = resolution else { continue }
                let bytes = await Task.detached { Self.totalBytes(of: [source]) }.value
                let shouldMove = move
                let manager = self
                let journalID = OperationJournal.shared.begin(
                    source: source,
                    target: target,
                    move: move
                )
                do {
                    try await Task.detached {
                        try ChunkedFileCopier.transfer(
                            source: source,
                            target: target,
                            move: shouldMove,
                            control: control
                        ) { bytes in
                            Task { @MainActor in
                                manager.update(id) { $0.completedBytes += bytes }
                            }
                        }
                    }.value
                    OperationJournal.shared.complete(journalID)
                } catch {
                    if FileManager.default.fileExists(atPath: source.path) {
                        try? FileManager.default.removeItem(at: target)
                    }
                    OperationJournal.shared.complete(journalID)
                    throw error
                }
                results.append(FileTransferResult(source: source, destination: target, wasMove: move))
                update(id) { operation in
                    operation.completedBytes = min(operation.totalBytes, max(operation.completedBytes, bytes))
                }
            }
            update(id) {
                if cancelled.contains(id) { $0.isCancelled = true }
                else { $0.completedBytes = $0.totalBytes }
                $0.finishedAt = Date()
            }
        } catch {
            update(id) {
                $0.error = error.localizedDescription
                $0.finishedAt = Date()
            }
        }
        paused.remove(id)
        cancelled.remove(id)
        controls.removeValue(forKey: id)
        return results
    }

    func togglePause(_ id: UUID) {
        if paused.contains(id) {
            paused.remove(id)
            controls[id]?.setPaused(false)
            update(id) { $0.isPaused = false }
        } else {
            paused.insert(id)
            controls[id]?.setPaused(true)
            update(id) { $0.isPaused = true }
        }
    }

    func cancel(_ id: UUID) {
        cancelled.insert(id)
        paused.remove(id)
        controls[id]?.cancel()
        update(id) {
            $0.isPaused = false
            $0.isCancelled = true
        }
    }

    private func update(_ id: UUID, _ body: (inout FileOperation) -> Void) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        body(&operations[index])
    }

    private func resolveTarget(
        for source: URL,
        in directory: URL,
        policy: ConflictPolicy
    ) throws -> URL? {
        let candidate = directory.appendingPathComponent(source.lastPathComponent)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        switch policy {
        case .skip:
            return nil
        case .replace:
            // Keep replacement recoverable. Finder-style replacement should
            // never permanently destroy the existing destination before the
            // incoming copy has had a chance to complete.
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: candidate, resultingItemURL: &trashedURL)
            return candidate
        case .keepBoth:
            return Self.uniqueDestination(for: source, in: directory)
        }
    }

    nonisolated static func transfer(source: URL, target: URL, move: Bool) throws {
        if move {
            do {
                try FileManager.default.moveItem(at: source, to: target)
            } catch {
                // Moving between volumes can fail as a rename. Copy and remove is
                // slower, but preserves Finder-style cross-volume behavior.
                try FileManager.default.copyItem(at: source, to: target)
                do {
                    try FileManager.default.removeItem(at: source)
                } catch {
                    try? FileManager.default.removeItem(at: target)
                    throw error
                }
            }
        } else {
            try FileManager.default.copyItem(at: source, to: target)
        }
    }

    nonisolated static func validate(source: URL, destination: URL, move: Bool) throws {
        guard move else { return }
        let sourcePath = source.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                NSLocalizedDescriptionKey: "A folder can’t be moved into itself or one of its subfolders."
            ])
        }
    }

    nonisolated static func uniqueDestination(for source: URL, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(source.lastPathComponent)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var number = 2
        repeat {
            let name = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            candidate = directory.appendingPathComponent(name)
            number += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    nonisolated static func totalBytes(of urls: [URL]) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        var total: Int64 = 0
        for url in urls {
            if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            } else if let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
            ) {
                for case let child as URL in enumerator {
                    if let values = try? child.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
                        total += Int64(values.fileSize ?? 0)
                    }
                }
            }
        }
        return total
    }
}
