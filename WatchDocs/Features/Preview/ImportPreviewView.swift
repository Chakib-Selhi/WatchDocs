import SwiftData
import SwiftUI
import WatchDocsKit

/// IOS-04: editable title, page count, estimated size and reading modes before sending.
struct ImportPreviewView: View {
    @Environment(DocumentPipeline.self) private var pipeline
    @Environment(\.dismiss) private var dismiss
    @Query private var documents: [SentDocument]
    let ids: [UUID]

    init(ids: [UUID]) {
        self.ids = ids
        let wanted = ids
        _documents = Query(filter: #Predicate<SentDocument> { wanted.contains($0.id) }, sort: \SentDocument.createdAt)
    }

    private var totalBytes: Int64 { documents.reduce(0) { $0 + $1.totalBytes } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(documents) { document in
                    PreviewRow(document: document)
                }
                Section {
                    LabeledContent("Total", value: ByteFormatting.string(totalBytes))
                    if let free = pipeline.watchContext?.freeBytes {
                        LabeledContent("Free on watch", value: ByteFormatting.string(free))
                    }
                    if !pipeline.linkState.isReachable {
                        Label("The watch is not reachable right now. Documents will be delivered automatically later.", systemImage: "clock")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(documents.count > 1 ? Text("\(documents.count) documents") : Text("Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        pipeline.discardPreview()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        pipeline.sendAll(documents.map(\.id))
                        dismiss()
                    } label: {
                        Text("Send").bold()
                    }
                    .accessibilityIdentifier("sendButton")
                }
            }
        }
    }
}

private struct PreviewRow: View {
    @Environment(DocumentPipeline.self) private var pipeline
    let document: SentDocument
    @State private var title = ""

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: document.sourceType.symbolName)
                    .font(.title)
                    .foregroundStyle(.tint)
                    .frame(width: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $title)
                        .font(.headline)
                        .onSubmit { pipeline.rename(document, to: title) }
                    HStack(spacing: 10) {
                        if document.pageCount > 0 {
                            Text("\(document.pageCount) pages")
                        }
                        Text(ByteFormatting.string(document.totalBytes))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    HStack {
                        ForEach(document.modes, id: \.self) { mode in
                            Text(mode.label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
        .onAppear { title = document.title }
        .onChange(of: title) { _, newValue in
            pipeline.rename(document, to: newValue)
        }
    }
}
