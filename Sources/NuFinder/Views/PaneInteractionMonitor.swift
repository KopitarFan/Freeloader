import AppKit
import SwiftUI

struct PaneInteractionMonitor: NSViewRepresentable {
    let onMouseDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMouseDown: onMouseDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = false
        context.coordinator.monitoredView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.monitoredView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        weak var monitoredView: NSView?
        var onMouseDown: () -> Void
        private var monitor: Any?

        init(onMouseDown: @escaping () -> Void) {
            self.onMouseDown = onMouseDown
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                guard let self,
                      let view = monitoredView,
                      event.window === view.window else {
                    return event
                }
                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else { return event }
                onMouseDown()
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
