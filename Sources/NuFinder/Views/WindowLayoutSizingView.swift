import AppKit
import SwiftUI

struct WindowLayoutSizingView: NSViewRepresentable {
    let minimumContentSize: CGSize

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let screenSize = window.screen.map {
                window.contentRect(forFrameRect: $0.visibleFrame).size
            } ?? minimumContentSize
            let minimum = NSSize(
                width: min(minimumContentSize.width, screenSize.width),
                height: min(minimumContentSize.height, screenSize.height)
            )
            window.contentMinSize = minimum

            let current = window.contentLayoutRect.size
            guard current.width < minimum.width || current.height < minimum.height else { return }
            let targetContent = NSSize(
                width: max(current.width, minimum.width),
                height: max(current.height, minimum.height)
            )
            var targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContent))
            targetFrame.origin = window.frame.origin
            targetFrame.origin.y -= targetFrame.height - window.frame.height

            if let visibleFrame = window.screen?.visibleFrame {
                targetFrame.size.width = min(targetFrame.width, visibleFrame.width)
                targetFrame.size.height = min(targetFrame.height, visibleFrame.height)
                targetFrame.origin.x = min(
                    max(targetFrame.origin.x, visibleFrame.minX),
                    visibleFrame.maxX - targetFrame.width
                )
                targetFrame.origin.y = min(
                    max(targetFrame.origin.y, visibleFrame.minY),
                    visibleFrame.maxY - targetFrame.height
                )
            }
            window.setFrame(targetFrame, display: true)
        }
    }
}
