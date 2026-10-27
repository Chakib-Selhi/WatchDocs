import SwiftUI
import WatchDocsKit

struct DocumentDetailView: View {
    @Environment(DocumentPipeline.self) private var pipeline
    @Environment(\.dismiss) private var dismiss
    let document: SentDocument
    @State private var title = ""
    @State private var confirmDelete = false
    @State private var isDeleted = false

    var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $title)
                    .submitLabel(.done)
                    .onSubmit { pipeline.rename(document, to: title) }
            }

            Section("Status") {
                StatusBadge(document: document)
                if document.status == .sending || document.status == .queued {
                    ProgressView(value: document.progress)
                    if document.status == .queued {
                        Text("The watch is not reachable. The document will be delivered automatically when it is nearby and unlocked.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let reason = document.failureReason, document.status == .failed {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if document.status == .failed || document.status == .ready {
                    Button {
                        pipeline.retry(document)
                    } label: {
                        Label(document.status == .ready ? "Send to watch" : "Retry", systemImage: "paperplane")
                    }
                }
            }

            Section("Details") {
                LabeledContent("Type") { Text(document.sourceType.label) }
                LabeledContent("Original file", value: document.originalFileName)
                if document.pageCount > 0 {
                    LabeledContent("Pages", value: "\(document.pageCount)")
                }
                if !document.modes.isEmpty {
                    LabeledContent("Reading modes") {
                        Text(document.modes.map { String(localized: $0.localizedName) }.joined(separator: ", "))
                    }
                }
                LabeledContent("Size", value: ByteFormatting.string(document.totalBytes))
                LabeledContent("Added") { Text(document.createdAt, style: .date) }
            }

            Section {
                Button("Delete from iPhone and watch", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { title = document.title }
        .onDisappear {
            if !isDeleted { pipeline.rename(document, to: title) }
        }
        .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isDeleted = true
                dismiss()
                pipeline.delete(document)
            }
        }
    }
}

extension ReadingMode {
    var localizedName: String.LocalizationValue {
        switch self {
        case .pages: "Pages"
        case .text: "Text"
        case .table: "Table"
        }
    }
}
