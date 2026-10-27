import SwiftUI
import WatchDocsKit

/// WCH-05: ScrollView + Text, Digital Crown scrolling, 4 font sizes (Dynamic Type aware).
/// The text is split into paragraphs and laid out lazily, so long texts open fast.
struct TextReader: View {
    let document: StoredDocument
    @State private var paragraphs: [String]?
    @State private var sizeLevel = ReadingPositions.textSize
    @State private var visible: Set<Int> = []

    private static let styles: [Font] = [.footnote, .body, .title3, .title2]

    var body: some View {
        Group {
            if let paragraphs {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(paragraphs.indices, id: \.self) { i in
                                Text(paragraphs[i])
                                    .font(Self.styles[sizeLevel])
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                                    .onAppear { visible.insert(i) }
                                    .onDisappear { visible.remove(i) }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .onAppear {
                        let saved = ReadingPositions.paragraph(for: document.id)
                        if saved > 0, saved < paragraphs.count {
                            proxy.scrollTo(saved, anchor: .top)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    sizeLevel = (sizeLevel + 1) % Self.styles.count
                    ReadingPositions.textSize = sizeLevel
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel(Text("Text size"))
            }
        }
        .onChange(of: visible) { _, newValue in
            if let first = newValue.min() { ReadingPositions.setParagraph(first, for: document.id) }
        }
        .task {
            guard paragraphs == nil, let file = document.manifest.textFile else { return }
            let url = document.url(for: file)
            paragraphs = await Task.detached(priority: .userInitiated) {
                Self.loadParagraphs(url: url)
            }.value
        }
    }

    nonisolated static func loadParagraphs(url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        // Keep paragraphs reasonably short so lazy layout stays smooth.
        var result: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.count <= 2_000 {
                result.append(String(line))
            } else {
                var start = line.startIndex
                while start < line.endIndex {
                    let end = line.index(start, offsetBy: 2_000, limitedBy: line.endIndex) ?? line.endIndex
                    result.append(String(line[start..<end]))
                    start = end
                }
            }
        }
        // Collapse runs of empty lines.
        var collapsed: [String] = []
        for paragraph in result {
            if paragraph.trimmingCharacters(in: .whitespaces).isEmpty, collapsed.last?.isEmpty == true { continue }
            collapsed.append(paragraph.trimmingCharacters(in: .whitespaces).isEmpty ? "" : paragraph)
        }
        return collapsed
    }
}
