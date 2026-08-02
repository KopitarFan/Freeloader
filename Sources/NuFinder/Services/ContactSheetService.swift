import AppKit
import PDFKit

enum ContactSheetService {
    private static let pageSize = CGSize(width: 792, height: 612)
    private static let margin: CGFloat = 36
    private static let columns = 4
    private static let rows = 3

    nonisolated static func writePNG(images: [FileItem], title: String, to url: URL) throws {
        let cellWidth: CGFloat = 360
        let cellHeight: CGFloat = 285
        let columns = min(4, max(1, images.count))
        let rows = max(1, Int(ceil(Double(images.count) / Double(columns))))
        let size = CGSize(
            width: CGFloat(columns) * cellWidth + margin * 2,
            height: CGFloat(rows) * cellHeight + margin * 2 + 54
        )
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawPage(images: images, title: title, page: 0, in: CGRect(origin: .zero, size: size), grid: (columns, rows))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func writePDF(images: [FileItem], title: String, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let perPage = columns * rows
        let pageCount = max(1, Int(ceil(Double(images.count) / Double(perPage))))
        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            let start = page * perPage
            let end = min(start + perPage, images.count)
            let pageImages = start < end ? Array(images[start..<end]) : []
            drawPage(images: pageImages, title: title, page: page, in: mediaBox, grid: (columns, rows))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
    }

    @MainActor
    static func printContactSheet(images: [FileItem], title: String) async throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Freeloader Contact Sheet \(UUID().uuidString).pdf")
        try await Task.detached {
            try writePDF(images: images, title: title, to: temporaryURL)
        }.value
        guard let document = PDFDocument(url: temporaryURL),
              let operation = document.printOperation(
                for: NSPrintInfo.shared,
                scalingMode: .pageScaleToFit,
                autoRotate: true
              ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    private nonisolated static func drawPage(
        images: [FileItem],
        title: String,
        page: Int,
        in bounds: CGRect,
        grid: (columns: Int, rows: Int)
    ) {
        NSColor.white.setFill()
        bounds.fill()
        let titleStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(24, bounds.width / 30), weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ]
        let heading = page == 0 ? title : "\(title) — Page \(page + 1)"
        heading.draw(at: CGPoint(x: margin, y: bounds.height - margin - 24), withAttributes: titleStyle)

        let top = bounds.height - margin - 54
        let availableWidth = bounds.width - margin * 2
        let availableHeight = top - margin
        let cellWidth = availableWidth / CGFloat(grid.columns)
        let cellHeight = availableHeight / CGFloat(grid.rows)
        let labelStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(9, min(14, cellWidth / 20))),
            .foregroundColor: NSColor.labelColor,
        ]

        for (index, item) in images.enumerated() {
            let column = index % grid.columns
            let row = index / grid.columns
            let cell = CGRect(
                x: margin + CGFloat(column) * cellWidth,
                y: top - CGFloat(row + 1) * cellHeight,
                width: cellWidth,
                height: cellHeight
            ).insetBy(dx: 8, dy: 8)
            let labelHeight: CGFloat = 24
            let imageRect = CGRect(
                x: cell.minX,
                y: cell.minY + labelHeight,
                width: cell.width,
                height: cell.height - labelHeight
            )
            if let image = NSImage(contentsOf: item.url) {
                image.draw(
                    in: aspectFit(image.size, inside: imageRect),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            }
            (item.name as NSString).draw(
                in: CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: labelHeight),
                withAttributes: labelStyle
            )
        }
    }

    private nonisolated static func aspectFit(_ size: CGSize, inside bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
