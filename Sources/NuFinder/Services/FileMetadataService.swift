import Darwin
import Foundation

struct ExtendedAttribute: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let value: Data

    var displayValue: String {
        if let text = String(data: value, encoding: .utf8),
           !text.unicodeScalars.contains(where: { $0.value < 0x09 }) {
            return text
        }
        return value.map { String(format: "%02x", $0) }.joined()
    }
}

enum FileMetadataService {
    static func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    static func setPermissions(_ mode: Int, at url: URL) throws {
        guard (0...0o7777).contains(mode) else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                NSLocalizedDescriptionKey: "Permissions must be an octal value from 0000 through 7777."
            ])
        }
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    static func extendedAttributes(at url: URL) throws -> [ExtendedAttribute] {
        let names: [String] = try url.path.withCString { path in
            let length = listxattr(path, nil, 0, 0)
            guard length >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            guard length > 0 else { return [] }
            var buffer = [CChar](repeating: 0, count: length)
            let result = listxattr(path, &buffer, buffer.count, 0)
            guard result >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            return buffer.split(separator: 0).map { bytes in
                String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return try names.sorted().map { name in
            let value = try readAttribute(name, at: url)
            return ExtendedAttribute(name: name, value: value)
        }
    }

    static func setAttribute(_ name: String, value: Data, at url: URL) throws {
        guard !name.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let result = url.path.withCString { path in
            name.withCString { attributeName in
                value.withUnsafeBytes { bytes in
                    setxattr(path, attributeName, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
        guard result == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    static func removeAttribute(_ name: String, at url: URL) throws {
        let result = url.path.withCString { path in
            name.withCString { removexattr(path, $0, 0) }
        }
        guard result == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    private static func readAttribute(_ name: String, at url: URL) throws -> Data {
        try url.path.withCString { path in
            try name.withCString { attributeName in
                let length = getxattr(path, attributeName, nil, 0, 0, 0)
                guard length >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
                var data = Data(count: length)
                let result = data.withUnsafeMutableBytes {
                    getxattr(path, attributeName, $0.baseAddress, $0.count, 0, 0)
                }
                guard result >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
                return data
            }
        }
    }
}
