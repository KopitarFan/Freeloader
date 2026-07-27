import SwiftUI

struct MetadataEditorView: View {
    let url: URL
    @State private var permissions = ""
    @State private var attributes: [ExtendedAttribute] = []
    @State private var newName = ""
    @State private var newValue = ""
    @State private var errorMessage: String?

    var body: some View {
        DisclosureGroup("Permissions and Extended Attributes") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Mode", text: $permissions)
                        .frame(width: 70)
                    Button("Apply Permissions") { applyPermissions() }
                }
                ForEach(attributes) { attribute in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(attribute.name).font(.caption.bold())
                            Text(attribute.displayValue)
                                .font(.caption.monospaced())
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            remove(attribute.name)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Attribute name", text: $newName)
                    TextField("UTF-8 value", text: $newValue)
                    Button("Set") { setAttribute() }
                        .disabled(newName.isEmpty)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.top, 8)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        do {
            permissions = String(format: "%04o", try FileMetadataService.permissions(at: url))
            attributes = try FileMetadataService.extendedAttributes(at: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyPermissions() {
        guard let mode = Int(permissions, radix: 8) else {
            errorMessage = "Enter an octal mode such as 0644."
            return
        }
        do {
            try FileMetadataService.setPermissions(mode, at: url)
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func setAttribute() {
        do {
            try FileMetadataService.setAttribute(
                newName,
                value: Data(newValue.utf8),
                at: url
            )
            newName = ""
            newValue = ""
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ name: String) {
        do {
            try FileMetadataService.removeAttribute(name, at: url)
            reload()
        } catch { errorMessage = error.localizedDescription }
    }
}
