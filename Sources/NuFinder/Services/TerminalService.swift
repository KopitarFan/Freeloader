import AppKit
import Foundation

enum TerminalService {
    static let applicationPathKey = "preferredTerminalPath"

    static func open(at url: URL) {
        let preferred = UserDefaults.standard.string(forKey: applicationPathKey)
            .map { URL(fileURLWithPath: $0) }
        let application = preferred.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        } ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: application,
            configuration: configuration
        )
    }

    static var installedApplications: [URL] {
        [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/iTerm.app",
            "/Applications/Warp.app",
            "/Applications/Alacritty.app",
            "/Applications/kitty.app"
        ]
        .map { URL(fileURLWithPath: $0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
