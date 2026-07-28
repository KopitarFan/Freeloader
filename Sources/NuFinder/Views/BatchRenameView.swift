import SwiftUI

enum RenameLetterCase: String, CaseIterable, Identifiable {
    case unchanged = "Unchanged"
    case lowercase = "lowercase"
    case uppercase = "UPPERCASE"
    case title = "Title Case"
    var id: Self { self }
}

struct BatchRenameRequest {
    var pattern = "{name}-{index}"
    var find = ""
    var replacement = ""
    var extensionOverride = ""
    var letterCase: RenameLetterCase = .unchanged
    var startIndex = 1
}

struct BatchRenameView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var request = BatchRenameRequest()

    private var selectedItems: [FileItem] {
        browser.displayedItems.filter { browser.selection.contains($0.url) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Batch Rename").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Rename") {
                    browser.batchRename(request)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedItems.isEmpty || previewNames.contains(""))
            }

            Form {
                TextField("Pattern", text: $request.pattern)
                HStack {
                    TextField("Find", text: $request.find)
                    TextField("Replace with", text: $request.replacement)
                }
                TextField("New extension (optional)", text: $request.extensionOverride)
                Picker("Letter case", selection: $request.letterCase) {
                    ForEach(RenameLetterCase.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Stepper("Starting number: \(request.startIndex)", value: $request.startIndex, in: 0...999_999)
                Text("Tokens: {name}, {index}, {ext}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Preview").font(.headline)
            List(Array(zip(selectedItems, previewNames)), id: \.0.id) { item, name in
                HStack {
                    Text(item.name).lineLimit(1)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Text(name.isEmpty ? "Invalid name" : name)
                        .lineLimit(1)
                        .foregroundStyle(name.isEmpty ? .red : .primary)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
    }

    private var previewNames: [String] {
        selectedItems.enumerated().map { offset, item in
            BrowserModel.renamedFilename(
                for: item,
                request: request,
                index: request.startIndex + offset
            ) ?? ""
        }
    }
}
