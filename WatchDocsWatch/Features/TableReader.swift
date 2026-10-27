import SwiftUI
import WatchDocsKit

/// WCH-06: grid scrollable in both directions, frozen header row, sheet choice.
struct TableReader: View {
    let document: StoredDocument
    @State private var sheetIndex: Int
    @State private var sheet: TableSheet?
    @State private var loadFailed = false
    @State private var showSheets = false

    private let columnWidth: CGFloat = 78

    init(document: StoredDocument) {
        self.document = document
        let saved = ReadingPositions.sheet(for: document.id)
        _sheetIndex = State(initialValue: min(max(0, saved), max(0, document.manifest.tableFiles.count - 1)))
    }

    private var sheetNames: [String] {
        let names = document.manifest.sheetNames
        return names.count == document.manifest.tableFiles.count
            ? names
            : document.manifest.tableFiles.indices.map { String(localized: "Sheet \($0 + 1)") }
    }

    var body: some View {
        Group {
            if let sheet {
                if sheet.rows.isEmpty {
                    Text("Empty sheet").foregroundStyle(.secondary)
                } else {
                    grid(sheet)
                }
            } else if loadFailed {
                Label("Sheet unavailable", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .toolbar {
            if sheetNames.count > 1 {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showSheets = true
                    } label: {
                        Label(sheetNames[sheetIndex], systemImage: "square.stack")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .accessibilityLabel(Text("Choose sheet"))
                }
            }
        }
        .sheet(isPresented: $showSheets) {
            List(sheetNames.indices, id: \.self) { i in
                Button {
                    sheetIndex = i
                    showSheets = false
                } label: {
                    HStack {
                        Text(sheetNames[i])
                        if i == sheetIndex {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .task(id: sheetIndex) {
            ReadingPositions.setSheet(sheetIndex, for: document.id)
            sheet = nil
            loadFailed = false
            let files = document.manifest.tableFiles
            guard sheetIndex < files.count else {
                loadFailed = true
                return
            }
            let url = document.url(for: files[sheetIndex])
            let loaded = await Task.detached(priority: .userInitiated) { () -> TableSheet? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? TableSheet.decode(from: data)
            }.value
            sheet = loaded
            loadFailed = loaded == nil
        }
    }

    private func grid(_ sheet: TableSheet) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(1..<max(1, sheet.rows.count), id: \.self) { r in
                        row(sheet.rows[r], header: false, striped: r % 2 == 0)
                    }
                } header: {
                    row(sheet.rows[0], header: true, striped: false)
                }
            }
        }
    }

    private func row(_ cells: [String], header: Bool, striped: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { c in
                Text(cells[c])
                    .font(header ? .caption2.bold() : .caption2)
                    .lineLimit(3)
                    .frame(width: columnWidth, alignment: .leading)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(.gray.opacity(0.4)).frame(width: 0.5)
                    }
            }
        }
        .background(header ? Color(white: 0.22) : (striped ? Color(white: 0.1) : Color.black))
        .accessibilityElement(children: .combine)
    }
}
