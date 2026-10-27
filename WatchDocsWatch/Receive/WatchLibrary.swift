import Foundation
import Observation
import WatchDocsKit

/// Watch side model: owns the WatchConnectivity link and exposes the document list.
@MainActor
@Observable
final class WatchLibrary {
    static let shared = WatchLibrary()

    let store: DocumentStore
    let receiver: WatchReceiver
    private(set) var documents: [StoredDocument] = []
    private(set) var linkState = LinkState()
    private var reloadTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?

    private init() {
        let store = DocumentStore(root: DocumentStore.defaultRoot())
        try? store.prepare()
        self.store = store
        let link = WatchConnectivityLink(stagingDirectory: store.stagingDirectory)
        receiver = WatchReceiver(link: link, store: store)
        reload()
        eventsTask = Task { [weak self] in
            guard let events = self?.receiver.events else { return }
            for await event in events {
                switch event {
                case .libraryChanged, .documentCompleted:
                    self?.scheduleReload()
                case .linkStateChanged(let state):
                    self?.linkState = state
                }
            }
        }
    }

    /// Reloads immediately (disk access off the main thread).
    func reload() {
        let store = store
        Task {
            let list = await Task.detached(priority: .userInitiated) { store.listDocuments() }.value
            self.documents = list
        }
    }

    /// Coalesces bursts of events (one per received page) into one reload.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    func delete(_ document: StoredDocument) {
        documents.removeAll { $0.id == document.id }
        ReadingPositions.forget(document.id)
        let receiver = receiver
        Task { await receiver.delete(docId: document.id) }
    }

    func document(id: UUID) -> StoredDocument? {
        documents.first { $0.id == id }
    }

    var usedBytes: Int64 {
        documents.reduce(0) { $0 + ($1.isComplete ? $1.manifest.totalBytes : 0) }
    }
}

/// WCH-10: last page, mode and text position per document.
enum ReadingPositions {
    private static var defaults: UserDefaults { .standard }

    static func page(for id: UUID) -> Int { defaults.integer(forKey: "page.\(id.uuidString)") }
    static func setPage(_ page: Int, for id: UUID) { defaults.set(page, forKey: "page.\(id.uuidString)") }

    static func paragraph(for id: UUID) -> Int { defaults.integer(forKey: "text.\(id.uuidString)") }
    static func setParagraph(_ index: Int, for id: UUID) { defaults.set(index, forKey: "text.\(id.uuidString)") }

    static func sheet(for id: UUID) -> Int { defaults.integer(forKey: "sheet.\(id.uuidString)") }
    static func setSheet(_ index: Int, for id: UUID) { defaults.set(index, forKey: "sheet.\(id.uuidString)") }

    static func mode(for id: UUID) -> ReadingMode? {
        defaults.string(forKey: "mode.\(id.uuidString)").flatMap(ReadingMode.init(rawValue:))
    }

    static func setMode(_ mode: ReadingMode, for id: UUID) { defaults.set(mode.rawValue, forKey: "mode.\(id.uuidString)") }

    static var textSize: Int {
        get { defaults.object(forKey: "textSize") as? Int ?? 1 }
        set { defaults.set(newValue, forKey: "textSize") }
    }

    static func forget(_ id: UUID) {
        for prefix in ["page.", "text.", "sheet.", "mode."] {
            defaults.removeObject(forKey: prefix + id.uuidString)
        }
    }
}
