import CoreXLSX
import Foundation
import PDFKit
import WatchDocsKit

/// .xlsx (CoreXLSX), .csv/.tsv (own parser), .xls/.numbers (WebKit best effort).
/// Table mode: one JSON per sheet. Pages mode: HTML tables printed to PDF.
enum ExcelConverter {
    /// Columns beyond this are dropped (unreadable on a watch anyway).
    static let maxColumns = 60

    static func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> DocumentPackage {
        let ext = request.sourceURL.pathExtension.lowercased()
        var sheets: [TableSheet] = []
        switch ext {
        case "xlsx":
            sheets = (try? readXLSX(request.sourceURL)) ?? []
        case "csv", "tsv":
            guard let data = try? Data(contentsOf: request.sourceURL) else { throw ConversionError.unreadable }
            let text = TextConverter.decode(data)
            let rows = CSVParser.parse(text, separator: ext == "tsv" ? "\t" : nil).map { Array($0.prefix(maxColumns)) }
            sheets = [TableSheet(name: request.title, rows: rows)]
        default:
            break
        }
        sheets = sheets.filter { !$0.rows.isEmpty }
        progress(0.2)

        // Table files
        let dir = request.outputDirectory
        var tableFiles: [(name: String, kind: FileKind)] = []
        for (index, sheet) in sheets.enumerated() {
            let name = PackageNaming.sheetFileName(index: index)
            try sheet.encoded().write(to: dir.appendingPathComponent(name))
            tableFiles.append((name, .table))
        }

        // Pages: HTML built from the sheets, or the original file through WebKit.
        let pdfData: Data?
        var webText: String? = nil
        if !sheets.isEmpty {
            let html = HTMLTableRenderer.html(for: sheets, title: request.title)
            pdfData = try? await renderHTML(html)
        } else {
            let rendered = try? await WordConverter.renderWithWebKit(request.sourceURL, wantText: true)
            pdfData = rendered?.pdf
            webText = rendered?.text
        }
        progress(0.4)

        let sheetNames = sheets.map(\.name)
        let tableModes: [ReadingMode] = sheets.isEmpty ? [] : [.table]

        if let pdfData, let document = PDFDocument(data: pdfData), document.pageCount > 0 {
            // Spreadsheets: table first, then pages. Text mode only for files we could not parse.
            return try await PDFConverter.convert(
                document: document,
                request: request,
                sourceType: .excel,
                extraText: sheets.isEmpty ? webText : "",
                extraFiles: tableFiles,
                sheetNames: sheetNames,
                extraModes: tableModes,
                progress: { progress(0.4 + 0.6 * $0) }
            )
        }
        guard !tableFiles.isEmpty else { throw ConversionError.renderFailed }
        progress(1)
        return try PackageBuilder.build(
            id: request.id,
            title: request.title,
            sourceType: .excel,
            modes: [.table],
            files: tableFiles,
            sheetNames: sheetNames,
            in: dir
        )
    }

    @MainActor
    static func renderHTML(_ html: String) async throws -> Data {
        let renderer = WebRenderer()
        try await renderer.load(html: html)
        return try await renderer.makePDF()
    }

    // MARK: XLSX

    static func readXLSX(_ url: URL) throws -> [TableSheet] {
        guard let file = XLSXFile(filepath: url.path) else { throw ConversionError.unreadable }
        let sharedStrings = try? file.parseSharedStrings()
        var result: [TableSheet] = []
        for workbook in try file.parseWorkbooks() {
            for (name, path) in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                let worksheet = try file.parseWorksheet(at: path)
                var grid: [Int: [Int: String]] = [:]
                var maxRow = 0
                var maxColumn = 0
                for row in worksheet.data?.rows ?? [] {
                    let rowIndex = Int(row.reference)
                    for cell in row.cells {
                        let column = columnIndex(cell.reference.column.value)
                        guard column > 0, column <= maxColumns else { continue }
                        let value = cellText(cell, sharedStrings: sharedStrings)
                        guard !value.isEmpty else { continue }
                        grid[rowIndex, default: [:]][column] = value
                        maxRow = max(maxRow, rowIndex)
                        maxColumn = max(maxColumn, column)
                    }
                }
                guard maxRow > 0, maxColumn > 0 else { continue }
                // Skip leading empty rows/columns.
                let firstRow = grid.keys.min() ?? 1
                let firstColumn = grid.values.flatMap(\.keys).min() ?? 1
                var rows: [[String]] = []
                rows.reserveCapacity(maxRow - firstRow + 1)
                for r in firstRow...maxRow {
                    let cells = grid[r] ?? [:]
                    rows.append((firstColumn...maxColumn).map { cells[$0] ?? "" })
                }
                result.append(TableSheet(name: name ?? "Sheet \(result.count + 1)", rows: rows))
            }
        }
        return result
    }

    /// "A" -> 1, "Z" -> 26, "AA" -> 27.
    static func columnIndex(_ letters: String) -> Int {
        letters.uppercased().unicodeScalars.reduce(0) { total, scalar in
            guard scalar.value >= 65, scalar.value <= 90 else { return total }
            return total * 26 + Int(scalar.value - 64)
        }
    }

    static func cellText(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        if cell.type == .sharedString {
            if let sharedStrings, let s = cell.stringValue(sharedStrings) { return s }
            return ""
        }
        if let inline = cell.inlineString?.text { return inline }
        guard let raw = cell.value else { return "" }
        if cell.type == .bool { return raw == "1" ? "TRUE" : "FALSE" }
        // Tidy numbers: 12.0 -> 12, 0.30000000000000004 -> 0.3
        if let number = Double(raw), cell.type == nil || cell.type == .number {
            if number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
            return String(format: "%.10g", number)
        }
        return raw
    }
}

/// Builds a printable HTML document from sheets.
enum HTMLTableRenderer {
    static func html(for sheets: [TableSheet], title: String) -> String {
        var html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { font: 13px -apple-system, Helvetica, sans-serif; color: #000; margin: 0; }
        h2 { font-size: 15px; margin: 12px 0 6px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #999; padding: 3px 5px; text-align: left; vertical-align: top; word-break: break-word; }
        th { background: #eee; }
        tr { page-break-inside: avoid; }
        thead { display: table-header-group; }
        </style></head><body>
        """
        for sheet in sheets {
            if sheets.count > 1 || sheet.name != title {
                html += "<h2>\(escape(sheet.name))</h2>"
            }
            html += "<table>"
            if let header = sheet.rows.first {
                html += "<thead><tr>" + header.map { "<th>\(escape($0))</th>" }.joined() + "</tr></thead>"
            }
            html += "<tbody>"
            for row in sheet.rows.dropFirst() {
                html += "<tr>" + row.map { "<td>\(escape($0))</td>" }.joined() + "</tr>"
            }
            html += "</tbody></table>"
        }
        html += "</body></html>"
        return html
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
