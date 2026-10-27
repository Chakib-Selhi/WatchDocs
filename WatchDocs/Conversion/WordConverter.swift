import Foundation
import PDFKit
import UIKit
import WatchDocsKit
import ZIPFoundation

/// .docx, .doc, .rtf (and .odt / .pages when WebKit can open them).
/// Pages mode: WebKit layout printed to PDF, then rasterized.
/// Text mode: XML of the .docx, attributed string for RTF, page text otherwise.
enum WordConverter {
    static func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> DocumentPackage {
        let ext = request.sourceURL.pathExtension.lowercased()
        var text: String? = nil
        var pdfData: Data? = nil

        switch ext {
        case "docx":
            text = docxText(at: request.sourceURL)
            pdfData = try? await renderWithWebKit(request.sourceURL, wantText: false).pdf
        case "rtf", "rtfd":
            let attributed = try? NSAttributedString(
                url: request.sourceURL,
                options: [.documentType: ext == "rtf" ? NSAttributedString.DocumentType.rtf : .rtfd],
                documentAttributes: nil
            )
            text = attributed?.string
            if let attributed {
                pdfData = await MainActor.run { WebRenderer.paginate(attributedText: attributed) }
            }
        default:
            let rendered = try? await renderWithWebKit(request.sourceURL, wantText: true)
            pdfData = rendered?.pdf
            text = rendered?.text
        }
        progress(0.3)

        let cleanText = text.map { TextDecoding.normalizeNewlines($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let hasText = !(cleanText ?? "").isEmpty

        if let pdfData, let document = PDFDocument(data: pdfData), document.pageCount > 0 {
            return try await PDFConverter.convert(
                document: document,
                request: request,
                sourceType: .word,
                extraText: hasText ? cleanText : nil,
                progress: { progress(0.3 + 0.7 * $0) }
            )
        }
        // Layout failed: Text mode only (PRD risk table).
        guard hasText, let cleanText else { throw ConversionError.renderFailed }
        try Data(cleanText.utf8).write(to: request.outputDirectory.appendingPathComponent(PackageNaming.textFileName))
        progress(1)
        return try PackageBuilder.build(
            id: request.id,
            title: request.title,
            sourceType: .word,
            modes: [.text],
            files: [(PackageNaming.textFileName, .text)],
            in: request.outputDirectory
        )
    }

    /// Text of `word/document.xml`.
    static func docxText(at url: URL) -> String? {
        guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil),
              let entry = archive["word/document.xml"]
        else { return nil }
        var xml = Data()
        do {
            _ = try archive.extract(entry, skipCRC32: true) { chunk in xml.append(chunk) }
        } catch {
            return nil
        }
        return WordXMLTextExtractor.extract(from: xml)
    }

    @MainActor
    static func renderWithWebKit(_ url: URL, wantText: Bool) async throws -> (pdf: Data, text: String?) {
        let renderer = WebRenderer()
        try await renderer.load(fileURL: url)
        let pdf = try await renderer.makePDF()
        let text = wantText ? await renderer.innerText() : nil
        return (pdf, text)
    }
}
