import SwiftUI
import WatchDocsKit

/// WCH-02: icon by type, title, date. Incomplete documents are marked "Receiving…".
struct LibraryView: View {
    @Environment(WatchLibrary.self) private var library

    var body: some View {
        Group {
            if library.documents.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No documents")
                            .font(.headline)
                        Text("Send files from WatchDocs on your iPhone.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                }
            } else {
                List {
                    ForEach(library.documents) { document in
                        if document.isComplete {
                            NavigationLink(value: document.id) {
                                DocumentRow(document: document)
                            }
                        } else {
                            DocumentRow(document: document)
                        }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { library.documents[$0] }
                        for document in targets { library.delete(document) }
                    }
                    Section {
                        Text("\(library.documents.count) documents · \(ByteFormatting.string(library.usedBytes))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle("WatchDocs")
        .navigationDestination(for: UUID.self) { id in
            if let document = library.document(id: id) {
                DocumentView(document: document)
            }
        }
    }
}

private struct DocumentRow: View {
    let document: StoredDocument

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: document.manifest.sourceType.symbolName)
                .font(.title3)
                .foregroundStyle(document.isComplete ? Color.accentColor : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.manifest.title)
                    .font(.headline)
                    .lineLimit(2)
                if document.isComplete {
                    Text(document.manifest.createdAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Receiving… \(Int(document.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    ProgressView(value: document.progress)
                        .tint(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
}

extension ReadingMode {
    var symbolName: String {
        switch self {
        case .pages: "doc.richtext"
        case .text: "text.alignleft"
        case .table: "tablecells"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .pages: "Pages"
        case .text: "Text"
        case .table: "Table"
        }
    }
}
