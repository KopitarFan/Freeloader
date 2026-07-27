import SwiftUI

struct FileInfoView: View {
    @EnvironmentObject private var browser: BrowserModel
    let item: FileItem
    private let byteFormatter = ByteCountFormatter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text(item.name).font(.title2.bold())
                    Text(item.kind).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            infoRow("Where", item.url.deletingLastPathComponent().path)
            infoRow("Size", item.isDirectory ? "Folder size is calculated during transfers" :
                        byteFormatter.string(fromByteCount: item.size))
            if let created = item.created {
                infoRow("Created", created.formatted(date: .long, time: .shortened))
            }
            if let modified = item.modified {
                infoRow("Modified", modified.formatted(date: .long, time: .shortened))
            }
            if let attributes = try? FileManager.default.attributesOfItem(atPath: item.url.path) {
                if let owner = attributes[.ownerAccountName] as? String {
                    infoRow("Owner", owner)
                }
                if let permissions = attributes[.posixPermissions] as? NSNumber {
                    infoRow("Permissions", String(format: "%03o", permissions.intValue))
                }
            }
            if let tags = try? item.url.resourceValues(forKeys: [.tagNamesKey]).tagNames,
               !tags.isEmpty {
                infoRow("Tags", tags.joined(separator: ", "))
            }
            MetadataEditorView(url: item.url)
            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                Spacer()
                Button("Done") { browser.itemForInfo = nil }
                    .keyboardShortcut(.defaultAction)
            }
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            Text(value).textSelection(.enabled)
        }
    }
}
