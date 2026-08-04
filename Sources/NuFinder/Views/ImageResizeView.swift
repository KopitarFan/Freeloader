import SwiftUI

struct ImageResizeView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    @State private var width = "1920"
    @State private var height = "1080"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "photo.badge.arrow.down")
                    .font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Resize Images").font(.title2.bold())
                    Text("Creates resized copies and preserves the originals.")
                        .foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { Text("Maximum width"); TextField("Width", text: $width).frame(width: 100); Text("px") }
                GridRow { Text("Maximum height"); TextField("Height", text: $height).frame(width: 100); Text("px") }
            }
            Text("Aspect ratio is preserved. Smaller images are left at their original size.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Resize") { resize() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(dimensions == nil)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var dimensions: (CGFloat, CGFloat)? {
        guard let width = Double(width), let height = Double(height), width > 0, height > 0 else { return nil }
        return (CGFloat(width), CGFloat(height))
    }

    private func resize() {
        guard let dimensions else { return }
        do {
            _ = try ImageActionService.resize(urls, maxWidth: dimensions.0, maxHeight: dimensions.1)
            browser.reload()
            dismiss()
        } catch {
            browser.errorMessage = "Couldn’t resize the image: \(error.localizedDescription)"
        }
    }
}
