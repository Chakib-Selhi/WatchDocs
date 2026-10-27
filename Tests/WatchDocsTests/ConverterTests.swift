import Foundation
import ImageIO
import Testing
import WatchDocsKit
@testable import WatchDocs

private final class BundleToken {}

/// Unit tests of the converters with the fixtures (PRD 9.2). Run on the iOS simulator.
@Suite("Converters", .serialized)
struct ConverterTests {
    private func fixture(_ name: String) throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        return try #require(bundle.url(forResource: parts[0], withExtension: parts[1]), "Missing fixture \(name)")
    }

    private func request(_ name: String, type: SourceType, password: String? = nil, quality: ConversionQuality = .standard) throws -> ConversionRequest {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("conv-" + UUID().uuidString, isDirectory: true)
        return ConversionRequest(
            id: UUID(),
            sourceURL: try fixture(name),
            title: SourceClassifier.title(forFileName: name),
            sourceType: type,
            options: ConversionOptions(quality: quality, format: .heic),
            preferredMode: .pages,
            password: password,
            outputDirectory: output
        )
    }

    private func pixelWidth(_ url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return props[kCGImagePropertyPixelWidth] as? Int
    }

    @Test("IOS-03: 20 page PDF converted in under 10 s")
    func pdfTwentyPages() async throws {
        let start = Date()
        let package = try await DocumentConverter.convert(try request("sample.pdf", type: .pdf)) { _ in }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 10, "Conversion took \(elapsed) s")
        #expect(package.manifest.pageCount == 20)
        #expect(package.manifest.modes == [.pages, .text])
        #expect(package.manifest.thumbnailFile != nil)
        #expect(package.allFilesPresent())
        let first = try #require(package.manifest.pageFiles.first)
        #expect(pixelWidth(package.url(for: first)) == ConversionQuality.standard.pageWidth)
        let text = try String(contentsOf: package.url(for: try #require(package.manifest.textFile)), encoding: .utf8)
        #expect(text.contains("page 20"))
    }

    @Test func qualityChangesWidth() async throws {
        let package = try await DocumentConverter.convert(try request("sample.pdf", type: .pdf, quality: .economy)) { _ in }
        let first = try #require(package.manifest.pageFiles.first)
        #expect(pixelWidth(package.url(for: first)) == 500)
    }

    @Test func protectedPDF() async throws {
        await #expect(throws: ConversionError.passwordRequired) {
            _ = try await DocumentConverter.convert(try request("sample-protected.pdf", type: .pdf)) { _ in }
        }
        await #expect(throws: ConversionError.wrongPassword) {
            _ = try await DocumentConverter.convert(try request("sample-protected.pdf", type: .pdf, password: "nope")) { _ in }
        }
        let package = try await DocumentConverter.convert(try request("sample-protected.pdf", type: .pdf, password: "watch")) { _ in }
        #expect(package.manifest.pageCount == 2)
    }

    @Test func image() async throws {
        let package = try await DocumentConverter.convert(try request("sample.png", type: .image)) { _ in }
        #expect(package.manifest.pageCount == 1)
        #expect(package.manifest.modes == [.pages])
        let page = try #require(package.manifest.pageFiles.first)
        let width = try #require(pixelWidth(package.url(for: page)))
        #expect(width <= ConversionQuality.standard.imageMaxDimension)
    }

    @Test("M5: UTF-8 and ISO-8859-1 text")
    func text() async throws {
        let utf8 = try await DocumentConverter.convert(try request("sample.txt", type: .text)) { _ in }
        #expect(utf8.manifest.modes == [.text])
        let latin = try await DocumentConverter.convert(try request("sample-latin1.txt", type: .text)) { _ in }
        let content = try String(contentsOf: latin.url(for: try #require(latin.manifest.textFile)), encoding: .utf8)
        #expect(content.hasPrefix("Café été à Montréal"))
    }

    @Test("M6: Word document gives text (and pages when WebKit can lay it out)")
    @MainActor
    func word() async throws {
        let package = try await DocumentConverter.convert(try request("sample.docx", type: .word)) { _ in }
        #expect(package.manifest.modes.contains(.text))
        let text = try String(contentsOf: package.url(for: try #require(package.manifest.textFile)), encoding: .utf8)
        #expect(text.contains("Notes de présentation"))
        #expect(text.contains("INF1120"))
    }

    @Test("M6: Excel workbook gives one table per sheet")
    @MainActor
    func excel() async throws {
        let package = try await DocumentConverter.convert(try request("sample.xlsx", type: .excel)) { _ in }
        #expect(package.manifest.modes.contains(.table))
        #expect(package.manifest.sheetNames == ["Horaire", "Budget"])
        let first = try TableSheet.decode(from: Data(contentsOf: package.url(for: package.manifest.tableFiles[0])))
        #expect(first.rows.first == ["Jour", "Heure", "Cours", "Local"])
        #expect(first.rows.count == 4)
        let budget = try TableSheet.decode(from: Data(contentsOf: package.url(for: package.manifest.tableFiles[1])))
        #expect(budget.rows[1] == ["Loyer", "850"])
        #expect(budget.rows[2] == ["Épicerie", "320.5"])
    }

    @Test @MainActor
    func csv() async throws {
        let package = try await DocumentConverter.convert(try request("sample.csv", type: .excel)) { _ in }
        let sheet = try TableSheet.decode(from: Data(contentsOf: package.url(for: package.manifest.tableFiles[0])))
        #expect(sheet.rows.count == 4)
        #expect(sheet.rows[2][0] == "Pain, blé entier")
    }

    @Test func modeOrderFollowsPreference() {
        #expect(DocumentConverter.order([.pages, .text], preferred: .text) == [.text, .pages])
        #expect(DocumentConverter.order([.pages, .table], preferred: .text) == [.pages, .table])
    }

    @Test func excelColumnLetters() {
        #expect(ExcelConverter.columnIndex("A") == 1)
        #expect(ExcelConverter.columnIndex("Z") == 26)
        #expect(ExcelConverter.columnIndex("AA") == 27)
        #expect(ExcelConverter.columnIndex("BC") == 55)
    }
}
