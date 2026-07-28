import AppKit
import QuickLookThumbnailing

final class ThumbnailService: @unchecked Sendable {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 96 * 1_024 * 1_024
    }

    func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))@\(scale)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }

        if let image {
            let cost = max(1, Int(size.width * size.height * scale * scale * 4))
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }
}
