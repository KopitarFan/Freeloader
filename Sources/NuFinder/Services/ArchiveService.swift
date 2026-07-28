import Foundation

enum ArchiveService {
    static let supportedExtensions = ["zip", "tar", "tgz", "gz", "bz2", "xz"]

    nonisolated static func isArchive(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func createZip(from sources: [URL], at destination: URL) throws {
        guard !sources.isEmpty else { return }
        let parent = sources[0].deletingLastPathComponent()
        guard sources.allSatisfy({ $0.deletingLastPathComponent() == parent }) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try run(
            "/usr/bin/zip",
            arguments: ["-r", "-q", destination.path] + sources.map(\.lastPathComponent),
            currentDirectory: parent
        )
    }

    nonisolated static func extract(_ archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            let ext = archive.pathExtension.lowercased()
            if ext == "zip" {
                try validateEntries(command: "/usr/bin/zipinfo", arguments: ["-1", archive.path])
                try run("/usr/bin/ditto", arguments: ["-x", "-k", archive.path, destination.path])
            } else {
                try validateEntries(command: "/usr/bin/tar", arguments: ["-tf", archive.path])
                try run("/usr/bin/tar", arguments: ["-xf", archive.path, "-C", destination.path])
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private nonisolated static func validateEntries(command: String, arguments: [String]) throws {
        let output = try run(command, arguments: arguments)
        for rawLine in output.split(separator: "\n") {
            let entry = String(rawLine)
            let components = entry.split(separator: "/", omittingEmptySubsequences: false)
            if entry.hasPrefix("/") || components.contains("..") {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    @discardableResult
    private nonisolated static func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "Archive operation failed."
            throw NSError(
                domain: "Freeloader.Archive",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
