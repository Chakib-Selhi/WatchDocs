import Foundation

/// Kind of source file the user imported on the iPhone.
public enum SourceType: String, Codable, Sendable, CaseIterable {
    case pdf, image, photo, word, excel, text
}

/// Ways a document can be read on the watch.
public enum ReadingMode: String, Codable, Sendable, CaseIterable {
    /// Rasterized page images.
    case pages
    /// Plain text.
    case text
    /// JSON tables (one per sheet).
    case table
}

/// Role of a single file inside a document package.
public enum FileKind: String, Codable, Sendable {
    case page, text, table, thumbnail, manifest
}

/// A file listed in the manifest. The watch uses it to validate reception.
public struct PackageFile: Codable, Sendable, Hashable {
    public let name: String
    public let kind: FileKind
    public let bytes: Int64
    public let sha256: String

    public init(name: String, kind: FileKind, bytes: Int64, sha256: String) {
        self.name = name
        self.kind = kind
        self.bytes = bytes
        self.sha256 = sha256
    }
}

/// Describes one converted document. Encoded as `manifest.json`.
public struct DocumentManifest: Codable, Sendable, Identifiable, Hashable {
    public static let currentSchemaVersion = 1
    public static let fileName = "manifest.json"

    public let id: UUID
    public var title: String
    public let sourceType: SourceType
    public let createdAt: Date
    public let modes: [ReadingMode]
    /// Number of page images. 0 when the document has no `.pages` mode.
    public let pageCount: Int
    /// Sum of all files listed in `files`.
    public let totalBytes: Int64
    public let files: [PackageFile]
    /// Sheet names, in the same order as the `.table` files. Empty otherwise.
    public let sheetNames: [String]
    public let schemaVersion: Int

    public init(
        id: UUID = UUID(),
        title: String,
        sourceType: SourceType,
        createdAt: Date = Date(),
        modes: [ReadingMode],
        pageCount: Int,
        files: [PackageFile],
        sheetNames: [String] = [],
        schemaVersion: Int = DocumentManifest.currentSchemaVersion
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.createdAt = createdAt
        self.modes = modes
        self.pageCount = pageCount
        self.files = files
        self.totalBytes = files.reduce(0) { $0 + $1.bytes }
        self.sheetNames = sheetNames
        self.schemaVersion = schemaVersion
    }

    // MARK: Convenience accessors

    /// Page files in page order.
    public var pageFiles: [PackageFile] {
        files.filter { $0.kind == .page }.sorted { PackageNaming.pageIndex($0.name) < PackageNaming.pageIndex($1.name) }
    }

    public var tableFiles: [PackageFile] {
        files.filter { $0.kind == .table }.sorted { PackageNaming.sheetIndex($0.name) < PackageNaming.sheetIndex($1.name) }
    }

    public var textFile: PackageFile? { files.first { $0.kind == .text } }
    public var thumbnailFile: PackageFile? { files.first { $0.kind == .thumbnail } }

    public var defaultMode: ReadingMode { modes.first ?? .pages }

    // MARK: Coding

    public func encoded() throws -> Data {
        try JSONCoding.encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> DocumentManifest {
        try JSONCoding.decoder.decode(DocumentManifest.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, sourceType, createdAt, modes, pageCount, totalBytes, files, sheetNames, schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceType = try c.decode(SourceType.self, forKey: .sourceType)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modes = try c.decode([ReadingMode].self, forKey: .modes)
        pageCount = try c.decode(Int.self, forKey: .pageCount)
        files = try c.decode([PackageFile].self, forKey: .files)
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? files.reduce(0) { $0 + $1.bytes }
        sheetNames = try c.decodeIfPresent([String].self, forKey: .sheetNames) ?? []
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

/// One spreadsheet sheet, encoded as `sheet_N.json`.
public struct TableSheet: Codable, Sendable, Hashable {
    public let name: String
    public let columns: Int
    public let rows: [[String]]

    public init(name: String, rows: [[String]]) {
        self.name = name
        let width = rows.map(\.count).max() ?? 0
        self.columns = width
        // Normalize every row to the same width so the grid is rectangular.
        self.rows = rows.map { row in
            row.count == width ? row : row + Array(repeating: "", count: width - row.count)
        }
    }

    public func encoded() throws -> Data { try JSONCoding.encoder.encode(self) }

    public static func decode(from data: Data) throws -> TableSheet {
        try JSONCoding.decoder.decode(TableSheet.self, from: data)
    }
}

public enum JSONCoding {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
