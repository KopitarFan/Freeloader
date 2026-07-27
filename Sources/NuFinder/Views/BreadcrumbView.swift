import SwiftUI

struct BreadcrumbView: View {
    @EnvironmentObject private var browser: BrowserModel

    private var components: [URL] {
        Self.componentURLs(for: browser.currentURL)
    }

    static func componentURLs(for url: URL) -> [URL] {
        let names = url.standardizedFileURL.pathComponents
        var result: [URL] = []
        var path = "/"
        result.append(URL(fileURLWithPath: path, isDirectory: true))
        for name in names.dropFirst() {
            path = (path as NSString).appendingPathComponent(name)
            result.append(URL(fileURLWithPath: path, isDirectory: true))
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Array(components.enumerated()), id: \.element) { index, url in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        browser.navigate(to: url)
                    } label: {
                        Label(
                            url.path == "/" ? "Macintosh HD" : url.lastPathComponent,
                            systemImage: index == components.count - 1 ? "folder.fill" : "folder"
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open in New Tab") { browser.newTab(at: url) }
                        Button("Open in New Window") { WindowService.open(at: url) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
