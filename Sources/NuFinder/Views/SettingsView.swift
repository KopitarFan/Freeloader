import SwiftUI

struct SettingsView: View {
    @AppStorage(TerminalService.applicationPathKey)
    private var terminalPath = "/System/Applications/Utilities/Terminal.app"

    var body: some View {
        Form {
            Picker("Terminal application", selection: $terminalPath) {
                ForEach(TerminalService.installedApplications, id: \.path) { application in
                    Text(application.deletingPathExtension().lastPathComponent)
                        .tag(application.path)
                }
            }
            Text("Used by the toolbar and Open in Terminal actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
