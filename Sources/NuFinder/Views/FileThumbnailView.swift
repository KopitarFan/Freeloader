import SwiftUI

struct FileThumbnailView: View {
    let item: FileItem
    let size: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(nsImage: item.icon)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.09)))
        .task(id: item.url) {
            thumbnail = nil
            guard item.isImage else { return }
            thumbnail = await ThumbnailService.shared.thumbnail(
                for: item.url,
                size: CGSize(width: size, height: size),
                scale: NSScreen.main?.backingScaleFactor ?? 2
            )
        }
    }
}
