import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ImagePreviewPane: View {
    let item: FileItem

    @State private var preview: NSImage?
    @State private var textPreview: String?
    @State private var metadata: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Button {
                    QuickLookService.shared.show([item.url])
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Open Quick Look")
            }

            if let textPreview {
                ScrollView {
                    Text(textPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    if let preview {
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(10)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }

            Text(item.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            Text(item.kind)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(metadata, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(
            minWidth: 260,
            idealWidth: 340,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .task(id: item.url) {
            preview = nil
            textPreview = nil
            metadata = []
            async let loadedPreview = ThumbnailService.shared.thumbnail(
                    for: item.url,
                    size: CGSize(width: 720, height: 720),
                    scale: NSScreen.main?.backingScaleFactor ?? 2
                )
            async let loadedDetails = Self.loadDetails(for: item)
            preview = await loadedPreview
            let details = await loadedDetails
            textPreview = details.text
            metadata = details.metadata
        }
    }

    private nonisolated static func loadDetails(for item: FileItem) -> (text: String?, metadata: [String]) {
        var details: [String] = []
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        details.append(formatter.string(fromByteCount: item.size))

        guard let type = UTType(filenameExtension: item.url.pathExtension) else {
            return (nil, details)
        }

        if type.conforms(to: .plainText) || type.conforms(to: .sourceCode) ||
            type.conforms(to: .json) || type.conforms(to: .xml) {
            if let handle = try? FileHandle(forReadingFrom: item.url) {
                defer { try? handle.close() }
                let data = (try? handle.read(upToCount: 96_000)) ?? Data()
                if let text = String(data: data, encoding: .utf8) {
                    return (text, details)
                }
            }
        }

        if type.conforms(to: .image),
           let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                details.append("\(width) × \(height) pixels")
            }
            if let profile = properties[kCGImagePropertyProfileName] as? String {
                details.append(profile)
            }
        }
        return (nil, details)
    }
}
