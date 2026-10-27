import Foundation

/// A converted document ready to be transferred: a folder that contains
/// `manifest.json` and every file the manifest lists.
public struct DocumentPackage: Sendable, Hashable {
    public var manifest: DocumentManifest
    public let directory: URL

    public init(manifest: DocumentManifest, directory: URL) {
        self.manifest = manifest
        self.directory = directory
    }

    public var manifestURL: URL { directory.appendingPathComponent(DocumentManifest.fileName) }

    public func url(for file: PackageFile) -> URL { directory.appendingPathComponent(file.name) }

    /// Files in transfer order: thumbnail first, then text and tables (small,
    /// make the document usable in Text mode early), then pages in order.
    public var transferOrder: [PackageFile] {
        let thumb = manifest.files.filter { $0.kind == .thumbnail }
        let text = manifest.files.filter { $0.kind == .text }
        let tables = manifest.tableFiles
        let pages = manifest.pageFiles
        return thumb + text + tables + pages
    }

    /// Loads a package previously written with `PackageBuilder`.
    public static func load(from directory: URL) throws -> DocumentPackage {
        let data = try Data(contentsOf: directory.appendingPathComponent(DocumentManifest.fileName))
        return DocumentPackage(manifest: try DocumentManifest.decode(from: data), directory: directory)
    }

    /// Rewrites `manifest.json` (used after a title change).
    public func saveManifest() throws {
        try manifest.encoded().write(to: manifestURL, options: .atomic)
    }

    public func allFilesPresent(fileManager: FileManager = .default) -> Bool {
        manifest.files.allSatisfy { fileManager.fileExists(atPath: url(for: $0).path) }
    }
}

public enum PackageError: Error, Equatable, Sendable {
    case emptyPackage
    case missingFile(String)
    case unsafeFileName(String)
}

/// Builds a manifest for the files already written into a package folder.
public enum PackageBuilder {
    /// Scans `directory`, hashes every file and writes `manifest.json`.
    ///
    /// - Parameters:
    ///   - files: the files to include, with their kind. Order does not matter.
    public static func build(
        id: UUID = UUID(),
        title: String,
        sourceType: SourceType,
        modes: [ReadingMode],
        files: [(name: String, kind: FileKind)],
        sheetNames: [String] = [],
        in directory: URL,
        createdAt: Date = Date()
    ) throws -> DocumentPackage {
        guard !files.isEmpty else { throw PackageError.emptyPackage }
        var entries: [PackageFile] = []
        entries.reserveCapacity(files.count)
        for file in files {
            guard PackageNaming.isSafe(file.name) else { throw PackageError.unsafeFileName(file.name) }
            let url = directory.appendingPathComponent(file.name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.int64Value
            else { throw PackageError.missingFile(file.name) }
            entries.append(PackageFile(name: file.name, kind: file.kind, bytes: size, sha256: try FileHasher.sha256(of: url)))
        }
        let pageCount = entries.filter { $0.kind == .page }.count
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let manifest = DocumentManifest(
            id: id,
            title: cleanTitle.isEmpty ? "Document" : cleanTitle,
            sourceType: sourceType,
            // ISO 8601 keeps whole seconds: truncate so the manifest survives a round trip unchanged.
            createdAt: Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down)),
            modes: modes,
            pageCount: modes.contains(.pages) ? pageCount : 0,
            files: entries,
            sheetNames: sheetNames
        )
        let package = DocumentPackage(manifest: manifest, directory: directory)
        try package.saveManifest()
        return package
    }
}
