import CoreGraphics
import Foundation
import PDFKit
import WatchDocsKit

/// PDF -> page images (+ extracted text when the PDF contains text).
/// No page limit: pages are rendered in small batches and written to disk
/// immediately, so memory use does not grow with the page count.
enum PDFConverter {
    /// Hard cap on the height of one rasterized page (very long receipts).
    static let maxPageHeightPixels = 8_000

    static func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> DocumentPackage {
        guard let document = PDFDocument(url: request.sourceURL) else { throw ConversionError.unreadable }
        try unlock(document, password: request.password)
        return try await convert(document: document, request: request, sourceType: .pdf, extraText: nil, progress: progress)
    }

    static func unlock(_ document: PDFDocument, password: String?) throws {
        guard document.isLocked else { return }
        guard let password, !password.isEmpty else { throw ConversionError.passwordRequired }
        guard document.unlock(withPassword: password) else { throw ConversionError.wrongPassword }
    }

    /// Shared by the Word and Excel converters once they produced a PDF.
    /// - Parameter extraText: text to use for the Text mode instead of the PDF text layer.
    static func convert(
        document: PDFDocument,
        request: ConversionRequest,
        sourceType: SourceType,
        extraText: String?,
        extraFiles: [(name: String, kind: FileKind)] = [],
        sheetNames: [String] = [],
        extraModes: [ReadingMode] = [],
        progress: @escaping ProgressHandler
    ) async throws -> DocumentPackage {
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw ConversionError.empty }
        let format = ImageEncoder.effectiveFormat(request.options.format)
        let dir = request.outputDirectory
        var files: [(name: String, kind: FileKind)] = extraFiles
        var textParts: [String] = []
        let wantsPDFText = extraText == nil

        var index = 0
        while index < pageCount {
            try Task.checkCancellation()
            let end = min(index + request.options.batchSize, pageCount)
            try autoreleasepool {
                for i in index..<end {
                    guard let page = document.page(at: i) else { continue }
                    let name = PackageNaming.pageFileName(index: i, fileExtension: format.fileExtension)
                    guard let image = render(page: page, width: request.options.quality.pageWidth) else {
                        throw ConversionError.renderFailed
                    }
                    try ImageEncoder.write(image, to: dir.appendingPathComponent(name), format: format, quality: request.options.quality.compression)
                    files.append((name, .page))
                    if wantsPDFText, let text = page.string {
                        textParts.append(text)
                    }
                    if i == 0, let thumb = render(page: page, width: ImageEncoder.thumbnailMaxPixels) {
                        let thumbName = PackageNaming.thumbnailFileName(fileExtension: format.fileExtension)
                        if (try? ImageEncoder.write(thumb, to: dir.appendingPathComponent(thumbName), format: format, quality: 0.6)) != nil {
                            files.append((thumbName, .thumbnail))
                        }
                    }
                }
            }
            index = end
            progress(Double(index) / Double(pageCount))
            await Task.yield()
        }

        var modes: [ReadingMode] = [.pages]
        let text = (extraText ?? textParts.joined(separator: "\n\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            try Data(TextDecoding.normalizeNewlines(text).utf8).write(to: dir.appendingPathComponent(PackageNaming.textFileName))
            files.append((PackageNaming.textFileName, .text))
            modes.append(.text)
        }
        modes += extraModes

        return try PackageBuilder.build(
            id: request.id,
            title: request.title,
            sourceType: sourceType,
            modes: DocumentConverter.order(modes, preferred: request.preferredMode),
            files: files,
            sheetNames: sheetNames,
            in: dir
        )
    }

    /// Renders one page into a white bitmap `width` pixels wide, honoring the page rotation.
    static func render(page: PDFPage, width: Int) -> CGImage? {
        guard let cgPage = page.pageRef else { return nil }
        let box = cgPage.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let rotated = abs(Int(cgPage.rotationAngle)) % 180 == 90
        let pageWidth = rotated ? box.height : box.width
        let pageHeight = rotated ? box.width : box.height

        var scale = CGFloat(width) / pageWidth
        if pageHeight * scale > CGFloat(maxPageHeightPixels) {
            scale = CGFloat(maxPageHeightPixels) / pageHeight
        }
        let pixelWidth = max(1, Int((pageWidth * scale).rounded()))
        let pixelHeight = max(1, Int((pageHeight * scale).rounded()))
        guard let context = ImageEncoder.makeWhiteContext(width: pixelWidth, height: pixelHeight) else { return nil }

        // Bitmap contexts use PDF-like coordinates (origin bottom-left).
        context.scaleBy(x: scale, y: scale)
        let target = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        context.concatenate(cgPage.getDrawingTransform(.mediaBox, rect: target, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(cgPage)
        return context.makeImage()
    }

    /// Page count without rendering (used by the preview).
    static func pageCount(of url: URL, password: String?) -> Int? {
        guard let document = PDFDocument(url: url) else { return nil }
        if document.isLocked, let password { _ = document.unlock(withPassword: password) }
        return document.isLocked ? nil : document.pageCount
    }
}
