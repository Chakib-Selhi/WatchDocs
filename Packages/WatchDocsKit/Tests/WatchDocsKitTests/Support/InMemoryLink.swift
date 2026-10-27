import Foundation
@testable import WatchDocsKit

/// In-memory `SessionLink` pair used to test the protocol without WCSession.
/// Deliveries are queued until `deliver(...)` is called so tests can reorder,
/// duplicate or drop them.
final class InMemoryLink: SessionLink, @unchecked Sendable {
    enum Delivery {
        case message(TransportMessage)
        case file(source: URL, metadata: FileMetadata)
        case context(WatchContext)
    }

    let incoming: AsyncStream<LinkEvent>
    let continuation: AsyncStream<LinkEvent>.Continuation
    weak var peer: InMemoryLink?
    let staging: URL
    private let lock = NSLock()
    private var queue: [Delivery] = []
    private var _context: WatchContext?
    private var outstanding: [FileMetadata] = []
    var linkState = LinkState(isActivated: true, isPaired: true, isCounterpartAppInstalled: true, isReachable: true)

    init(staging: URL) {
        self.staging = staging
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let (stream, cont) = AsyncStream<LinkEvent>.makeStream()
        incoming = stream
        continuation = cont
    }

    static func pair(root: URL) -> (phone: InMemoryLink, watch: InMemoryLink) {
        let phone = InMemoryLink(staging: root.appendingPathComponent("phone-staging"))
        let watch = InMemoryLink(staging: root.appendingPathComponent("watch-staging"))
        phone.peer = watch
        watch.peer = phone
        return (phone, watch)
    }

    var state: LinkState { linkState }
    var receivedContext: WatchContext? { lock.withLock { _context } }

    func activate() {
        continuation.yield(.stateChanged(linkState))
    }

    func send(_ message: TransportMessage) throws {
        lock.withLock { queue.append(.message(message)) }
    }

    func transferFile(_ url: URL, metadata: FileMetadata) throws {
        // Snapshot the file now, like WCSession would read it.
        let copy = staging.appendingPathComponent("out-" + UUID().uuidString)
        try FileManager.default.copyItem(at: url, to: copy)
        lock.withLock {
            queue.append(.file(source: copy, metadata: metadata))
            outstanding.append(metadata)
        }
    }

    func cancelTransfers(docId: UUID) {
        lock.withLock {
            queue.removeAll {
                if case .file(_, let m) = $0 { return m.docId == docId }
                return false
            }
            outstanding.removeAll { $0.docId == docId }
        }
    }

    func outstandingTransfers() -> [FileMetadata] { lock.withLock { outstanding } }

    func updateContext(_ context: WatchContext) throws {
        lock.withLock { queue.append(.context(context)) }
    }

    var pendingCount: Int { lock.withLock { queue.count } }

    /// Takes the queued deliveries out.
    func drain() -> [Delivery] {
        lock.withLock {
            let q = queue
            queue.removeAll()
            return q
        }
    }

    /// Delivers queued items to the peer, optionally shuffled.
    @discardableResult
    func deliver(shuffled: Bool = false, duplicateFiles: Bool = false) -> Int {
        var items = drain()
        if duplicateFiles {
            items += items.filter { if case .file = $0 { return true } else { return false } }
        }
        if shuffled { items.shuffle() }
        for item in items { deliverOne(item) }
        return items.count
    }

    func deliverOne(_ item: Delivery) {
        guard let peer else { return }
        switch item {
        case .message(let m):
            peer.continuation.yield(.message(m))
        case .context(let c):
            peer.lock.withLock { peer._context = c }
            peer.continuation.yield(.context(c))
        case .file(let source, let metadata):
            let dest = peer.staging.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.copyItem(at: source, to: dest)
            peer.continuation.yield(.file(url: dest, metadata: metadata))
            lock.withLock {
                if let i = outstanding.firstIndex(of: metadata) { outstanding.remove(at: i) }
            }
            continuation.yield(.fileTransferFinished(metadata: metadata, errorDescription: nil))
        }
    }
}

enum TestFiles {
    static func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wdtests-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a fake package with `pages` page files, a text file and a thumbnail.
    static func makePackage(pages: Int, in root: URL, title: String = "Sample", pageBytes: Int = 64) throws -> DocumentPackage {
        let dir = root.appendingPathComponent("pkg-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [(name: String, kind: FileKind)] = []
        for i in 0..<pages {
            let name = PackageNaming.pageFileName(index: i, fileExtension: "heic")
            var bytes = Data(count: pageBytes)
            bytes.withUnsafeMutableBytes { raw in
                for j in 0..<raw.count { raw[j] = UInt8((i &* 31 &+ j) & 0xFF) }
            }
            try bytes.write(to: dir.appendingPathComponent(name))
            files.append((name, .page))
        }
        try Data("Hello \(title)".utf8).write(to: dir.appendingPathComponent(PackageNaming.textFileName))
        files.append((PackageNaming.textFileName, .text))
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("thumb.heic"))
        files.append(("thumb.heic", .thumbnail))
        return try PackageBuilder.build(title: title, sourceType: .pdf, modes: [.pages, .text], files: files, in: dir)
    }
}
