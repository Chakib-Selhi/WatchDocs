import Foundation

/// A document as stored on the watch.
public struct StoredDocument: Sendable, Identifiable, Hashable {
    public let manifest: DocumentManifest
    public let directory: URL
    public let isComplete: Bool
    /// Number of manifest files already on disk.
    public let receivedFiles: Int

    public var id: UUID { manifest.id }
    public var progress: Double {
        manifest.files.isEmpty ? 1 : Double(receivedFiles) / Double(manifest.files.count)
    }

    public func url(for file: PackageFile) -> URL { directory.appendingPathComponent(file.name) }
}

/// Folder layout of the watch storage (PRD 6.3):
///
///     <root>/Documents/<uuid>/manifest.json + files
///     <root>/Pending/<uuid>/files that arrived before their manifest
///     <root>/Staging/files moved out of the WatchConnectivity inbox
public struct DocumentStore: Sendable {
    public static let completeMarker = ".complete"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Application Support/WatchDocs` in the app container.
    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WatchDocs", isDirectory: true)
    }

    public var documentsDirectory: URL { root.appendingPathComponent("Documents", isDirectory: true) }
    public var pendingDirectory: URL { root.appendingPathComponent("Pending", isDirectory: true) }
    public var stagingDirectory: URL { root.appendingPathComponent("Staging", isDirectory: true) }

    public func directory(for id: UUID) -> URL {
        documentsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func pendingDirectory(for id: UUID) -> URL {
        pendingDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func prepare() throws {
        let fm = FileManager.default
        for dir in [documentsDirectory, pendingDirectory, stagingDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        Self.applyProtection(to: root)
    }

    /// Protects files at rest while still allowing background reception
    /// once the device was unlocked after boot (PRD section 7).
    public static func applyProtection(to url: URL) {
        #if os(iOS) || os(watchOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    public func manifest(for id: UUID) -> DocumentManifest? {
        let url = directory(for: id).appendingPathComponent(DocumentManifest.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? DocumentManifest.decode(from: data)
    }

    public func isComplete(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: id).appendingPathComponent(Self.completeMarker).path)
    }

    /// Lists every document that has a manifest, newest first.
    public func listDocuments() -> [StoredDocument] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil) else { return [] }
        var result: [StoredDocument] = []
        for dir in entries {
            guard let id = UUID(uuidString: dir.lastPathComponent), let manifest = manifest(for: id) else { continue }
            let complete = isComplete(id)
            let received: Int
            if complete {
                received = manifest.files.count
            } else {
                let names = Set((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
                received = manifest.files.filter { names.contains($0.name) }.count
            }
            result.append(StoredDocument(manifest: manifest, directory: dir, isComplete: complete, receivedFiles: received))
        }
        return result.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    /// Manifest files not yet on disk for an incomplete document.
    public func missingFileNames(for id: UUID) -> [String] {
        guard !isComplete(id), let manifest = manifest(for: id) else { return [] }
        let present = Set((try? FileManager.default.contentsOfDirectory(atPath: directory(for: id).path)) ?? [])
        return manifest.files.map(\.name).filter { !present.contains($0) }
    }

    /// Documents whose files are only in `Pending` (manifest never arrived).
    public func documentsWaitingForManifest() -> [UUID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: pendingDirectory.path)) ?? []
        return names.compactMap(UUID.init(uuidString:)).filter { manifest(for: $0) == nil }
    }

    /// Last time something was written in the document (or pending) folder.
    public func lastActivity(for id: UUID) -> Date? {
        let candidates = [directory(for: id), pendingDirectory(for: id)]
        return candidates.compactMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }.max()
    }

    public func document(id: UUID) -> StoredDocument? {
        listDocuments().first { $0.id == id }
    }

    /// Bytes used by received documents (from manifests, fast).
    public func usedBytes() -> Int64 {
        listDocuments().reduce(0) { total, doc in
            total + (doc.isComplete ? doc.manifest.totalBytes : Int64(Double(doc.manifest.totalBytes) * doc.progress))
        }
    }

    public func freeBytes() -> Int64? {
        #if os(iOS) || os(macOS)
        if let important = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        #endif
        #if canImport(Darwin)
        if let plain = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity {
            return Int64(plain)
        }
        #endif
        return nil
    }

    public func context() -> WatchContext {
        let docs = listDocuments()
        return WatchContext(
            documentCount: docs.filter(\.isComplete).count,
            usedBytes: usedBytes(),
            freeBytes: freeBytes()
        )
    }
}
