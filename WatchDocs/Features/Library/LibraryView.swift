import SwiftData
import SwiftUI
import WatchDocsKit

/// IOS-06: list of sent documents, search by title, sort by date, swipe to delete.
struct LibraryView: View {
    @Environment(DocumentPipeline.self) private var pipeline
    @Query(sort: \SentDocument.createdAt, order: .reverse) private var documents: [SentDocument]
    @State private var search = ""
    @State private var newestFirst = true

    private var filtered: [SentDocument] {
        let base = search.isEmpty
            ? documents
            : documents.filter { $0.title.localizedCaseInsensitiveContains(search) }
        return newestFirst ? base : base.reversed()
    }

    var body: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView {
                    Label("No documents", systemImage: "doc.on.doc")
                } description: {
                    Text("Tap + to send PDFs, photos, Word, Excel or text files to your Apple Watch. You can also use “Send to Watch” in the share sheet.")
                }
            } else {
                List {
                    ForEach(filtered) { document in
                        NavigationLink(value: document.id) {
                            DocumentRow(document: document)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pipeline.delete(document)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if document.status == .failed || document.status == .ready {
                                Button {
                                    pipeline.retry(document)
                                } label: {
                                    Label(document.status == .ready ? "Send" : "Retry", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $search, prompt: Text("Search by title"))
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            newestFirst.toggle()
                        } label: {
                            Label(newestFirst ? "Newest first" : "Oldest first", systemImage: "arrow.up.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Text("\(documents.count) documents")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            if let document = documents.first(where: { $0.id == id }) {
                DocumentDetailView(document: document)
            }
        }
    }
}

struct DocumentRow: View {
    let document: SentDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.sourceType.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    StatusBadge(document: document)
                    if document.pageCount > 0 {
                        Text("\(document.pageCount) pages")
                    }
                    if document.totalBytes > 0 {
                        Text(ByteFormatting.string(document.totalBytes))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if document.status == .sending || document.status == .queued {
                    ProgressView(value: document.progress)
                        .accessibilityLabel(Text("Transfer progress"))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let document: SentDocument

    var body: some View {
        Label {
            Text(document.status.label)
        } icon: {
            Image(systemName: document.status.symbolName)
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(document.status.color)
    }
}

extension DeliveryStatus {
    var label: LocalizedStringKey {
        switch self {
        case .converting: "Converting"
        case .ready: "Ready to send"
        case .queued: "Waiting for watch"
        case .sending: "Sending"
        case .delivered: "Delivered"
        case .failed: "Failed"
        }
    }

    var symbolName: String {
        switch self {
        case .converting: "gearshape.2"
        case .ready: "paperplane"
        case .queued: "clock"
        case .sending: "arrow.up.circle"
        case .delivered: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .delivered: .green
        case .failed: .red
        case .sending, .converting: .blue
        case .queued: .orange
        case .ready: .secondary
        }
    }
}

extension SourceType {
    var symbolName: String {
        switch self {
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .photo: "photo.on.rectangle"
        case .word: "doc.text"
        case .excel: "tablecells"
        case .text: "text.alignleft"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .pdf: "PDF"
        case .image: "Image"
        case .photo: "Photo"
        case .word: "Word"
        case .excel: "Spreadsheet"
        case .text: "Text"
        }
    }
}

extension ReadingMode {
    var label: LocalizedStringKey {
        switch self {
        case .pages: "Pages"
        case .text: "Text"
        case .table: "Table"
        }
    }
}
