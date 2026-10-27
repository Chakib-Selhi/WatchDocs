import Foundation

/// Watch side: puts received files in place, validates them against the
/// manifest and decides when a document is complete (PRD 6.3 and 6.4).
///
/// Files can arrive in any order, twice, or before their manifest.
/// A document is only marked complete when every manifest file is on disk
/// and its SHA-256 matches.
public actor DocumentAssembler {
    public enum Outcome: Sendable, Equatable {
        /// Nothing visible changed (duplicate, unknown file, deleted document).
        case ignored
        /// File stored, document still incomplete (or manifest still missing).
        case progress(docId: UUID)
        /// Every file is present and verified.
        case completed(docId: UUID)
        /// Some files failed verification and were discarded.
        case rejected(docId: UUID, names: [String])
    }

    public nonisolated let store: DocumentStore
    private var received: [UUID: Set<String>] = [:]
    private var manifests: [UUID: DocumentManifest] = [:]
    private var tombstones: [UUID] = []
    private let maxTombstones = 1000

    public init(store: DocumentStore) {
        self.store = store
        try? store.prepare()
        if let data = try? Data(contentsOf: store.root.appendingPathComponent("tombstones.json")),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            tombstones = ids
        }
    }

    // MARK: Reception

    /// Handles one incoming file. The file at `url` is moved or deleted.
    public func receive(fileAt url: URL, metadata: FileMetadata) -> Outcome {
        let id = metadata.docId
        if tombstones.contains(id) {
            try? FileManager.default.removeItem(at: url)
            return .ignored
        }
        if metadata.kind == .manifest {
            return receiveManifest(at: url, docId: id)
        }
        guard PackageNaming.isSafe(metadata.name) else {
            try? FileManager.default.removeItem(at: url)
            return .ignored
        }
        if let manifest = loadManifest(id) {
            return place(fileAt: url, name: metadata.name, manifest: manifest)
        }
        // Manifest not here yet: keep the file aside (PRD 6.4, step 6).
        do {
            let dir = store.pendingDirectory(for: id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Self.replaceItem(at: dir.appendingPathComponent(metadata.name), with: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return .rejected(docId: id, names: [metadata.name])
        }
        return .progress(docId: id)
    }

    private func receiveManifest(at url: URL, docId: UUID) -> Outcome {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: url),
              let manifest = try? DocumentManifest.decode(from: data),
              manifest.id == docId,
              manifest.files.allSatisfy({ PackageNaming.isSafe($0.name) })
        else {
            try? fm.removeItem(at: url)
            return .rejected(docId: docId, names: [DocumentManifest.fileName])
        }
        let dir = store.directory(for: docId)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Self.replaceItem(at: dir.appendingPathComponent(DocumentManifest.fileName), with: url)
        } catch {
            try? fm.removeItem(at: url)
            return .rejected(docId: docId, names: [DocumentManifest.fileName])
        }
        manifests[docId] = manifest
        if store.isComplete(docId) {
            // Retry of a document already received: confirm again.
            return .completed(docId: docId)
        }
        // Files that arrived before the manifest.
        var rejectedNames: [String] = []
        let pending = store.pendingDirectory(for: docId)
        if let names = try? fm.contentsOfDirectory(atPath: pending.path) {
            for name in names {
                let outcome = place(fileAt: pending.appendingPathComponent(name), name: name, manifest: manifest, checkCompletion: false)
                if case .rejected(_, let bad) = outcome { rejectedNames += bad }
            }
            try? fm.removeItem(at: pending)
        }
        if !rejectedNames.isEmpty { return .rejected(docId: docId, names: rejectedNames) }
        return checkCompletion(docId: docId, manifest: manifest)
    }

    private func place(fileAt url: URL, name: String, manifest: DocumentManifest, checkCompletion check: Bool = true) -> Outcome {
        let fm = FileManager.default
        let id = manifest.id
        guard let entry = manifest.files.first(where: { $0.name == name }) else {
            try? fm.removeItem(at: url)
            return .ignored
        }
        var names = receivedNames(id)
        if names.contains(name) {
            try? fm.removeItem(at: url)
            return check ? checkCompletion(docId: id, manifest: manifest) : .ignored
        }
        // Verify size then hash before accepting the file.
        let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? -1
        let hash = size == entry.bytes ? (try? FileHasher.sha256(of: url)) : nil
        guard hash == entry.sha256 else {
            try? fm.removeItem(at: url)
            return .rejected(docId: id, names: [name])
        }
        do {
            try Self.replaceItem(at: store.directory(for: id).appendingPathComponent(name), with: url)
        } catch {
            try? fm.removeItem(at: url)
            return .rejected(docId: id, names: [name])
        }
        names.insert(name)
        received[id] = names
        return check ? checkCompletion(docId: id, manifest: manifest) : .progress(docId: id)
    }

    private func checkCompletion(docId: UUID, manifest: DocumentManifest) -> Outcome {
        let names = receivedNames(docId)
        let missing = manifest.files.contains { !names.contains($0.name) }
        if missing { return .progress(docId: docId) }
        let marker = store.directory(for: docId).appendingPathComponent(DocumentStore.completeMarker)
        _ = FileManager.default.createFile(atPath: marker.path, contents: Data())
        received[docId] = nil
        manifests[docId] = nil
        return .completed(docId: docId)
    }

    // MARK: Changes from the user or the iPhone

    public func delete(docId: UUID) {
        let fm = FileManager.default
        try? fm.removeItem(at: store.directory(for: docId))
        try? fm.removeItem(at: store.pendingDirectory(for: docId))
        received[docId] = nil
        manifests[docId] = nil
        if !tombstones.contains(docId) {
            tombstones.append(docId)
            if tombstones.count > maxTombstones { tombstones.removeFirst(tombstones.count - maxTombstones) }
            if let data = try? JSONEncoder().encode(tombstones) {
                try? data.write(to: store.root.appendingPathComponent("tombstones.json"), options: .atomic)
            }
        }
    }

    public func rename(docId: UUID, title: String) {
        guard var manifest = store.manifest(for: docId) else { return }
        manifest.title = title
        if let data = try? manifest.encoded() {
            try? data.write(to: store.directory(for: docId).appendingPathComponent(DocumentManifest.fileName), options: .atomic)
        }
        manifests[docId] = manifest
    }

    public func isDeleted(_ docId: UUID) -> Bool { tombstones.contains(docId) }

    /// Removes leftovers of interrupted receptions (staging files older than `age`).
    /// Their documents recover through `WatchReceiver.requestMissingFiles`.
    public func cleanStaging(olderThan age: TimeInterval = 600, now: Date = Date()) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: store.stagingDirectory.path) else { return }
        for name in names {
            let url = store.stagingDirectory.appendingPathComponent(name)
            let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? .distantPast
            if now.timeIntervalSince(modified) > age { try? fm.removeItem(at: url) }
        }
    }

    // MARK: Helpers

    private func loadManifest(_ id: UUID) -> DocumentManifest? {
        if let cached = manifests[id] { return cached }
        let manifest = store.manifest(for: id)
        manifests[id] = manifest
        return manifest
    }

    private func receivedNames(_ id: UUID) -> Set<String> {
        if let cached = received[id] { return cached }
        let dir = store.directory(for: id)
        var names = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        names.remove(DocumentManifest.fileName)
        names.remove(DocumentStore.completeMarker)
        received[id] = names
        return names
    }

    static func replaceItem(at destination: URL, with source: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: source, to: destination)
    }
}
