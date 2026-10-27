import Foundation

/// Events the iPhone side observes.
public enum TransportEvent: Sendable, Equatable {
    /// The watch confirmed that the whole document arrived intact.
    case delivered(docId: UUID)
    /// The user deleted the document on the watch.
    case deletedOnWatch(docId: UUID)
    /// One outgoing file finished (success) — used to refresh progress.
    case fileSent(docId: UUID, name: String)
    /// One outgoing file failed.
    case fileFailed(docId: UUID, name: String, reason: String)
    /// The watch asks for some files again (hash mismatch).
    case resendRequested(docId: UUID, names: [String])
    case linkStateChanged(LinkState)
    case watchContextChanged(WatchContext)
}

/// Transport abstraction from the PRD (section 6.4). V1 uses WatchConnectivity,
/// V2 can add a CloudKit implementation without touching the app.
public protocol DocumentTransport: Sendable {
    func send(_ package: DocumentPackage) async throws
    func resend(_ package: DocumentPackage, names: [String]) async throws
    func delete(documentId: UUID) async throws
    func rename(documentId: UUID, title: String) async throws
    /// Fraction of files already handed over to the watch, or nil if nothing is in flight.
    func progress(for documentId: UUID, totalFiles: Int) async -> Double?
    var linkState: LinkState { get }
    var watchContext: WatchContext? { get }
    var events: AsyncStream<TransportEvent> { get }
}

/// iPhone side implementation on top of any `SessionLink`.
public final class PhoneTransport: DocumentTransport {
    private let link: SessionLink
    public let events: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let listener: Task<Void, Never>

    public init(link: SessionLink) {
        self.link = link
        let (stream, continuation) = AsyncStream<TransportEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
        let incoming = link.incoming
        listener = Task {
            for await event in incoming {
                switch event {
                case .message(.ack(let id)):
                    continuation.yield(.delivered(docId: id))
                case .message(.delete(let id)):
                    continuation.yield(.deletedOnWatch(docId: id))
                case .message(.resend(let id, let names)):
                    continuation.yield(.resendRequested(docId: id, names: names))
                case .message(.rename):
                    break // only the iPhone renames
                case .fileTransferFinished(let metadata, let error):
                    if let error {
                        continuation.yield(.fileFailed(docId: metadata.docId, name: metadata.name, reason: error))
                    } else {
                        continuation.yield(.fileSent(docId: metadata.docId, name: metadata.name))
                    }
                case .stateChanged(let state):
                    continuation.yield(.linkStateChanged(state))
                case .context(let context):
                    continuation.yield(.watchContextChanged(context))
                case .file:
                    break // the watch never sends files to the iPhone in V1
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
    public var watchContext: WatchContext? { link.receivedContext }

    /// Checks that the package fits in the free space the watch reported.
    /// Unknown free space is accepted: the watch will refuse if really full.
    public static func checkStorage(packageBytes: Int64, context: WatchContext?, userLimit: Int64?) throws {
        let safetyMargin: Int64 = 20 * 1024 * 1024
        if let context, let free = context.freeBytes, packageBytes + safetyMargin > free {
            throw TransportError.insufficientWatchStorage(needed: packageBytes, available: max(0, free - safetyMargin))
        }
        if let userLimit, let context {
            let available = userLimit - context.usedBytes
            if packageBytes > available {
                throw TransportError.insufficientWatchStorage(needed: packageBytes, available: max(0, available))
            }
        }
    }

    public func send(_ package: DocumentPackage) async throws {
        let state = link.state
        guard state.isActivated else { throw TransportError.notActivated }
        guard state.isPaired else { throw TransportError.watchNotPaired }
        // isWatchAppInstalled can be wrong after a direct install from Xcode:
        // a status received from the watch app proves it is installed.
        guard state.isCounterpartAppInstalled || link.receivedContext != nil else {
            throw TransportError.watchAppNotInstalled
        }

        let id = package.manifest.id
        // Manifest first so the watch can show "Receiving..." right away.
        // It travels as a file: with unlimited pages it can exceed userInfo limits.
        try link.transferFile(package.manifestURL, metadata: FileMetadata(docId: id, name: DocumentManifest.fileName, kind: .manifest, index: -1))
        for (index, file) in package.transferOrder.enumerated() {
            try link.transferFile(package.url(for: file), metadata: FileMetadata(docId: id, name: file.name, kind: file.kind, index: index))
        }
    }

    public func resend(_ package: DocumentPackage, names: [String]) async throws {
        let id = package.manifest.id
        let wanted = Set(names)
        if wanted.contains(DocumentManifest.fileName) {
            try link.transferFile(package.manifestURL, metadata: FileMetadata(docId: id, name: DocumentManifest.fileName, kind: .manifest, index: -1))
        }
        for (index, file) in package.transferOrder.enumerated() where wanted.contains(file.name) {
            try link.transferFile(package.url(for: file), metadata: FileMetadata(docId: id, name: file.name, kind: file.kind, index: index))
        }
    }

    public func delete(documentId: UUID) async throws {
        link.cancelTransfers(docId: documentId)
        try link.send(.delete(docId: documentId))
    }

    public func rename(documentId: UUID, title: String) async throws {
        try link.send(.rename(docId: documentId, title: title))
    }

    public func progress(for documentId: UUID, totalFiles: Int) async -> Double? {
        let remaining = link.outstandingTransfers().filter { $0.docId == documentId }.count
        guard remaining > 0, totalFiles > 0 else { return nil }
        // +1 accounts for the manifest file.
        let total = Double(totalFiles + 1)
        return max(0, min(1, (total - Double(remaining)) / total))
    }
}
