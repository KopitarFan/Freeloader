import Darwin
import Foundation

final class TransferControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var paused = false
    private var cancelled = false

    func setPaused(_ value: Bool) {
        condition.lock()
        paused = value
        condition.broadcast()
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        cancelled = true
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    func checkpoint() throws {
        condition.lock()
        while paused && !cancelled { condition.wait() }
        let shouldCancel = cancelled
        condition.unlock()
        if shouldCancel { throw CocoaError(.userCancelled) }
    }
}

enum ChunkedFileCopier {
    static let chunkSize = 1024 * 1024

    static func transfer(
        source: URL,
        target: URL,
        move: Bool,
        control: TransferControl,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws {
        try control.checkpoint()
        if move && sameVolume(source, target.deletingLastPathComponent()) {
            let bytes = FileOperationManager.totalBytes(of: [source])
            try FileManager.default.moveItem(at: source, to: target)
            progress(bytes)
            return
        }

        let partial = target.deletingLastPathComponent()
            .appendingPathComponent(".nufinder-partial-\(UUID().uuidString)")
        do {
            try copyNode(source, to: partial, control: control, progress: progress)
            try control.checkpoint()
            try FileManager.default.moveItem(at: partial, to: target)
            if move { try FileManager.default.removeItem(at: source) }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    private static func copyNode(
        _ source: URL,
        to target: URL,
        control: TransferControl,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws {
        try control.checkpoint()
        let values = try source.resourceValues(forKeys: [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey
        ])

        if values.isSymbolicLink == true {
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: source.path)
            try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: destination)
            return
        }

        if values.isDirectory == true {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let children = try FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: []
            )
            for child in children {
                try copyNode(
                    child,
                    to: target.appendingPathComponent(child.lastPathComponent),
                    control: control,
                    progress: progress
                )
            }
            copyMetadata(from: source, to: target)
            return
        }

        if values.isRegularFile == true {
            FileManager.default.createFile(atPath: target.path, contents: nil)
            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: target)
            defer {
                try? input.close()
                try? output.close()
            }
            while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
                try control.checkpoint()
                try output.write(contentsOf: data)
                progress(Int64(data.count))
            }
            try output.synchronize()
            copyMetadata(from: source, to: target)
            return
        }

        try FileManager.default.copyItem(at: source, to: target)
    }

    private static func copyMetadata(from source: URL, to target: URL) {
        source.path.withCString { sourcePath in
            target.path.withCString { targetPath in
                _ = copyfile(sourcePath, targetPath, nil, copyfile_flags_t(COPYFILE_METADATA))
            }
        }
    }

    private static func sameVolume(_ source: URL, _ destination: URL) -> Bool {
        let sourceVolume = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let destinationVolume = try? destination.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let sourceVolume, let destinationVolume else { return false }
        return String(describing: sourceVolume) == String(describing: destinationVolume)
    }
}
