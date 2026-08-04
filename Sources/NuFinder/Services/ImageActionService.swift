import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageActionService {
    enum Rotation { case left, right }
    enum OutputFormat { case png, jpeg }

    static func rotate(_ urls: [URL], direction: Rotation) throws -> [URL] {
        try urls.map { url in
            guard let image = CIImage(contentsOf: url) else { throw CocoaError(.fileReadCorruptFile) }
            let rotated = image.oriented(direction == .left ? .left : .right)
            return try write(rotated, beside: url, suffix: direction == .left ? "rotated-left" : "rotated-right", format: format(for: url))
        }
    }

    static func resize(_ urls: [URL], maxWidth: CGFloat, maxHeight: CGFloat) throws -> [URL] {
        guard maxWidth > 0, maxHeight > 0 else { throw CocoaError(.validationMissingMandatoryProperty) }
        return try urls.map { url in
            guard let image = CIImage(contentsOf: url) else { throw CocoaError(.fileReadCorruptFile) }
            let extent = image.extent
            let scale = min(1, maxWidth / extent.width, maxHeight / extent.height)
            let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return try write(resized, beside: url, suffix: "resized", format: format(for: url))
        }
    }

    static func convert(_ urls: [URL], to format: OutputFormat) throws -> [URL] {
        try urls.map { url in
            guard let image = CIImage(contentsOf: url) else { throw CocoaError(.fileReadCorruptFile) }
            return try write(image, beside: url, suffix: "converted", format: format)
        }
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    private static func write(
        _ image: CIImage,
        beside source: URL,
        suffix: String,
        format: OutputFormat
    ) throws -> URL {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let ext = format == .png ? "png" : "jpg"
        let base = source.deletingPathExtension().lastPathComponent + "-" + suffix
        let destination = uniqueURL(in: source.deletingLastPathComponent(), base: base, extension: ext)
        let type: UTType = format == .png ? .png : .jpeg
        guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let properties: CFDictionary? = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
            : nil
        CGImageDestinationAddImage(writer, cgImage, properties)
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
        return destination
    }

    private static func uniqueURL(in directory: URL, base: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    private static func format(for url: URL) -> OutputFormat {
        url.pathExtension.lowercased() == "png" ? .png : .jpeg
    }
}
