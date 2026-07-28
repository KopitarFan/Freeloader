import AppKit
import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

enum ChecksumAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case md5 = "MD5"
    case sha1 = "SHA-1"
    case sha256 = "SHA-256"
    var id: Self { self }
}

enum FileActionService {
    private static let finderTagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    static func copyPaths(_ urls: [URL], asFileURLs: Bool = false) {
        let text = urls.map { asFileURLs ? $0.absoluteString : $0.path }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func copyNames(_ urls: [URL]) {
        let text = urls.map(\.lastPathComponent).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func openWithApplications(for url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func sha256(of url: URL) throws -> String {
        try checksum(of: url, algorithm: .sha256)
    }

    static func checksum(of url: URL, algorithm: ChecksumAlgorithm) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        switch algorithm {
        case .md5:
            var hash = Insecure.MD5()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                hash.update(data: data)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha1:
            var hash = Insecure.SHA1()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                hash.update(data: data)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha256:
            var hash = SHA256()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                hash.update(data: data)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    @MainActor
    static func setDefaultApplication(_ application: URL, for url: URL) async throws {
        let values = try url.resourceValues(forKeys: [.contentTypeKey])
        guard let type = values.contentType else { throw CocoaError(.fileReadUnknown) }
        try await NSWorkspace.shared.setDefaultApplication(
            at: application,
            toOpen: type
        )
    }

    static func compare(_ urls: [URL]) throws {
        guard urls.count == 2 else { throw CocoaError(.fileReadUnknown) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
        process.arguments = urls.map(\.path)
        try process.run()
    }

    static func setFinderTags(_ tags: [String], on url: URL) throws {
        let path = url.path
        if tags.isEmpty {
            let result = path.withCString { pathPointer in
                finderTagsAttribute.withCString { attributePointer in
                    removexattr(pathPointer, attributePointer, 0)
                }
            }
            if result != 0, errno != ENOATTR {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return
        }

        // Finder stores tag names as a binary property-list extended attribute.
        // A newline plus color index may follow a name; plain names use index 0.
        let encodedTags = tags.map { "\($0)\n0" }
        let data = try PropertyListSerialization.data(
            fromPropertyList: encodedTags,
            format: .binary,
            options: 0
        )
        let result = data.withUnsafeBytes { bytes in
            path.withCString { pathPointer in
                finderTagsAttribute.withCString { attributePointer in
                    setxattr(pathPointer, attributePointer, bytes.baseAddress, data.count, 0, 0)
                }
            }
        }
        if result != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
