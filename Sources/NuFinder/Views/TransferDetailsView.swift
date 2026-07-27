import SwiftUI

struct TransferDetailsView: View {
    @EnvironmentObject private var operations: FileOperationManager
    private let formatter = ByteCountFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("File Operations").font(.title2.bold())
                Picker("When an item exists", selection: $operations.conflictPolicy) {
                    ForEach(ConflictPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .frame(width: 190)
                Spacer()
                Button("Done") { operations.showsDetails = false }
                    .keyboardShortcut(.defaultAction)
            }
            if operations.operations.isEmpty {
                ContentUnavailableView("No File Operations", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(operations.operations) { operation in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(operation.isMove ? "Moving" : "Copying")
                                .font(.headline)
                            Text(operation.sourceNames.joined(separator: ", "))
                                .lineLimit(1)
                            Spacer()
                            status(operation)
                        }
                        ProgressView(value: operation.progress)
                        HStack {
                            Text("\(formatter.string(fromByteCount: operation.completedBytes)) of \(formatter.string(fromByteCount: operation.totalBytes))")
                            Spacer()
                            Text("\(formatter.string(fromByteCount: Int64(operation.bytesPerSecond)))/s")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text("To: \(operation.destination.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let error = operation.error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        if operation.finishedAt == nil {
                            HStack {
                                Button(operation.isPaused ? "Resume" : "Pause") {
                                    operations.togglePause(operation.id)
                                }
                                Button("Cancel", role: .destructive) {
                                    operations.cancel(operation.id)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 320)
    }

    @ViewBuilder
    private func status(_ operation: FileOperation) -> some View {
        if operation.error != nil {
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if operation.isCancelled {
            Label("Cancelled", systemImage: "xmark.circle.fill")
                .foregroundStyle(.orange)
        } else if operation.finishedAt != nil {
            Label("Complete", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Text(operation.currentItem).foregroundStyle(.secondary)
        }
    }
}
