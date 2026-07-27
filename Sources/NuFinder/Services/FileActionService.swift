import AppKit
import CryptoKit
import Foundation

enum FileActionService {
    static func copyPaths(_ urls: [URL], asFileURLs: Bool = false) {
        let text = urls.map { asFileURLs ? $0.absoluteString : $0.path }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func openWithApplications(for url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
