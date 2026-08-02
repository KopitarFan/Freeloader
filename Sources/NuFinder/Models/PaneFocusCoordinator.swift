import Foundation

@MainActor
final class PaneFocusCoordinator: ObservableObject {
    @Published var activeBrowser: BrowserModel?

    func activate(_ browser: BrowserModel) {
        activeBrowser = browser
    }

    func isActive(_ browser: BrowserModel) -> Bool {
        activeBrowser === browser
    }
}
