import Foundation

/// Watch side of the protocol: consumes link events, feeds the assembler,
/// acknowledges complete documents and publishes the watch context.
public final class WatchReceiver: Sendable {
    public enum Event: Sendable, Equatable {
        /// The library changed (new file, new document, deletion, rename).
        case libraryChanged
        case documentCompleted(UUID)
        case linkStateChanged(LinkState)
    }

    public let assembler: DocumentAssembler
    private let link: SessionLink
    public let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let listener: Task<Void, Never>

    public init(link: SessionLink, store: DocumentStore) {
        self.link = link
        let assembler = DocumentAssembler(store: store)
        self.assembler = assembler
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
        let incoming = link.incoming
        listener = Task {
            for await event in incoming {
                switch event {
                case .file(let url, let metadata):
                    let outcome = await assembler.receive(fileAt: url, metadata: metadata)
                    switch outcome {
                    case .ignored:
                        break
                    case .progress:
                        continuation.yield(.libraryChanged)
                    case .completed(let id):
                        try? link.send(.ack(docId: id))
                        try? link.updateContext(store.context())
                        continuation.yield(.documentCompleted(id))
                        continuation.yield(.libraryChanged)
                    case .rejected(let id, let names):
                        try? link.send(.resend(docId: id, names: names))
                        continuation.yield(.libraryChanged)
                    }
                case .message(.delete(let id)):
                    await assembler.delete(docId: id)
                    try? link.updateContext(store.context())
                    continuation.yield(.libraryChanged)
                case .message(.rename(let id, let title)):
                    await assembler.rename(docId: id, title: title)
                    continuation.yield(.libraryChanged)
                case .message(.ack), .message(.resend):
                    break // iPhone-bound messages
                case .stateChanged(let state):
                    if state.isActivated { try? link.updateContext(store.context()) }
                    continuation.yield(.linkStateChanged(state))
                case .fileTransferFinished, .context:
                    break
                }
            }
            continuation.finish()
        }
        link.activate()
    }

    deinit {
        listener.cancel()
        continuation.finish()
    }

    public var linkState: LinkState { link.state }

    /// User deleted a document on the watch: remove it and tell the iPhone (WCH-08).
    public func delete(docId: UUID) async {
        await assembler.delete(docId: docId)
        try? link.send(.delete(docId: docId))
        try? link.updateContext(assembler.store.context())
        continuation.yield(.libraryChanged)
    }

    /// Asks the iPhone again for files of documents that stopped progressing
    /// (for example the app was killed between reception and storage).
    /// Duplicates are harmless, so this is safe even if transfers are still queued.
    @discardableResult
    public func requestMissingFiles(idleFor interval: TimeInterval = 120, now: Date = Date()) -> Int {
        let store = assembler.store
        var requests = 0
        for document in store.listDocuments() where !document.isComplete {
            if let last = store.lastActivity(for: document.id), now.timeIntervalSince(last) < interval { continue }
            let missing = store.missingFileNames(for: document.id)
            guard !missing.isEmpty else { continue }
            try? link.send(.resend(docId: document.id, names: missing))
            requests += 1
        }
        for id in store.documentsWaitingForManifest() {
            if let last = store.lastActivity(for: id), now.timeIntervalSince(last) < interval { continue }
            try? link.send(.resend(docId: id, names: [DocumentManifest.fileName]))
            requests += 1
        }
        return requests
    }

    public func publishContext() {
        try? link.updateContext(assembler.store.context())
    }
}
