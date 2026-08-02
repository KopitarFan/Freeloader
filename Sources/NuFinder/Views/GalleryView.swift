import SwiftUI
import UniformTypeIdentifiers

private enum GalleryMode: String, CaseIterable, Identifiable {
    case contactSheet = "Contact Sheet"
    case viewer = "Viewer"

    var id: Self { self }
}

struct GalleryView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: GalleryMode = .contactSheet
    @State private var selectedURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?

    private var images: [FileItem] {
        browser.displayedItems.filter(\.isImage)
    }

    private var selectedIndex: Int? {
        guard let selectedURL else { return nil }
        return images.firstIndex { $0.url == selectedURL }
    }

    var body: some View {
        VStack(spacing: 0) {
            galleryToolbar
            Divider()
            Group {
                if images.isEmpty {
                    ContentUnavailableView(
                        "No Images Here",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("This gallery only shows images in the current folder.")
                    )
                } else if mode == .contactSheet {
                    contactSheet
                } else {
                    viewer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, idealWidth: 980, minHeight: 520, idealHeight: 700)
        .onAppear {
            if let selected = browser.selection.first,
               images.contains(where: { $0.url == selected }) {
                selectedURL = selected
                mode = .viewer
            } else {
                selectedURL = images.first?.url
            }
        }
        .onMoveCommand(perform: moveSelection)
        .alert("Contact Sheet", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var galleryToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .foregroundStyle(.tint)
            Text(browser.currentURL.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
            Text("\(images.count) image\(images.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Gallery Mode", selection: $mode) {
                ForEach(GalleryMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            Menu {
                Button("Save as PNG…") { chooseExport(format: .png) }
                Button("Save as PDF…") { chooseExport(format: .pdf) }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(images.isEmpty || isExporting)
            Button {
                printContactSheet()
            } label: {
                Label("Print", systemImage: "printer")
            }
            .disabled(images.isEmpty || isExporting)
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
        .background(.bar)
    }

    private enum ExportFormat {
        case png
        case pdf

        var extensionName: String { self == .png ? "png" : "pdf" }
    }

    private func chooseExport(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .png ? [.png] : [.pdf]
        panel.nameFieldStringValue = "\(browser.currentURL.lastPathComponent) Contact Sheet.\(format.extensionName)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        let items = images
        let title = browser.currentURL.lastPathComponent
        Task {
            do {
                try await Task.detached {
                    switch format {
                    case .png: try ContactSheetService.writePNG(images: items, title: title, to: url)
                    case .pdf: try ContactSheetService.writePDF(images: items, title: title, to: url)
                    }
                }.value
            } catch {
                exportError = "Couldn’t save the contact sheet: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    private func printContactSheet() {
        isExporting = true
        let items = images
        let title = browser.currentURL.lastPathComponent
        Task {
            do {
                try await ContactSheetService.printContactSheet(images: items, title: title)
            } catch {
                exportError = "Couldn’t print the contact sheet: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    private var contactSheet: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)],
                spacing: 12
            ) {
                ForEach(images) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        GalleryImage(url: item.url, size: CGSize(width: 360, height: 260))
                            .frame(height: 130)
                            .frame(maxWidth: .infinity)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(7)
                    .background(
                        selectedURL == item.url ? Color.accentColor.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedURL = item.url }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            selectedURL = item.url
                            mode = .viewer
                        }
                    )
                }
            }
            .padding(16)
        }
    }

    private var viewer: some View {
        VStack(spacing: 10) {
            HStack {
                galleryNavigationButton("chevron.left", action: previousImage)
                Spacer()
                if let selectedIndex {
                    Text("\(selectedIndex + 1) of \(images.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                galleryNavigationButton("chevron.right", action: nextImage)
            }
            .padding(.horizontal, 18)

            if let selectedURL {
                GalleryImage(url: selectedURL, size: CGSize(width: 1800, height: 1400))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 18)
                Text(selectedURL.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .padding(.bottom, 12)
            }
        }
        .padding(.top, 12)
    }

    private func galleryNavigationButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FreeloaderToolbarIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .left, .up: previousImage()
        case .right, .down: nextImage()
        @unknown default: break
        }
    }

    private func previousImage() {
        guard !images.isEmpty else { return }
        let index = selectedIndex ?? 0
        selectedURL = images[(index - 1 + images.count) % images.count].url
    }

    private func nextImage() {
        guard !images.isEmpty else { return }
        let index = selectedIndex ?? -1
        selectedURL = images[(index + 1) % images.count].url
    }
}

private struct GalleryImage: View {
    let url: URL
    let size: CGSize
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: url) {
            image = nil
            image = await ThumbnailService.shared.thumbnail(
                for: url,
                size: size,
                scale: NSScreen.main?.backingScaleFactor ?? 2
            )
        }
    }
}
