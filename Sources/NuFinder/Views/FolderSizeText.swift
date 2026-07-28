import SwiftUI

struct FolderSizeText: View {
    let item: FileItem

    @ObservedObject private var sizes = FolderSizeService.shared

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Group {
            if let bytes = sizes.size(for: item) {
                Text(Self.formatter.string(fromByteCount: bytes))
            } else if sizes.calculating.contains(item.url) {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Text("—")
            }
        }
        .task(id: item.url) {
            sizes.calculate(item)
        }
    }
}
