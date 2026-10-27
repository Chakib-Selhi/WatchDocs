import SwiftUI
import WatchDocsKit

/// Opens a document in its default (or last used) mode. WCH-09: switch between modes.
struct DocumentView: View {
    let document: StoredDocument
    @State private var mode: ReadingMode
    @State private var showModes = false

    init(document: StoredDocument) {
        self.document = document
        let saved = ReadingPositions.mode(for: document.id)
        let initial = saved.flatMap { document.manifest.modes.contains($0) ? $0 : nil } ?? document.manifest.defaultMode
        _mode = State(initialValue: initial)
    }

    var body: some View {
        content
            .navigationTitle(document.manifest.title)
            .toolbar {
                if document.manifest.modes.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showModes = true
                        } label: {
                            Image(systemName: mode.symbolName)
                        }
                        .accessibilityLabel(Text("Reading mode"))
                    }
                }
            }
            .sheet(isPresented: $showModes) {
                List(document.manifest.modes, id: \.self) { candidate in
                    Button {
                        mode = candidate
                        ReadingPositions.setMode(candidate, for: document.id)
                        showModes = false
                    } label: {
                        Label(candidate.label, systemImage: candidate.symbolName)
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .pages:
            PageReader(document: document)
        case .text:
            TextReader(document: document)
        case .table:
            TableReader(document: document)
        }
    }
}
