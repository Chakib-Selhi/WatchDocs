#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// `SessionLink` backed by `WCSession.default`.
///
/// Only one instance should exist per process because it becomes the
/// session delegate. Create it as early as possible (app launch) so that
/// queued transfers are delivered even when the app starts in background.
public final class WatchConnectivityLink: NSObject, SessionLink, WCSessionDelegate, @unchecked Sendable {
    public let incoming: AsyncStream<LinkEvent>
    private let continuation: AsyncStream<LinkEvent>.Continuation
    private let stagingDirectory: URL
    private let session: WCSession
    private let lock = NSLock()
    private var _receivedContext: WatchContext?

    /// - Parameter stagingDirectory: where received files are moved before
    ///   `session(_:didReceive:)` returns.
    public init(stagingDirectory: URL) {
        self.stagingDirectory = stagingDirectory
        self.session = WCSession.default
        let (stream, continuation) = AsyncStream<LinkEvent>.makeStream(bufferingPolicy: .unbounded)
        self.incoming = stream
        self.continuation = continuation
        super.init()
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
    }

    public static var isSupported: Bool { WCSession.isSupported() }

    public func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    public var state: LinkState {
        guard WCSession.isSupported() else { return LinkState() }
        #if os(iOS)
        return LinkState(
            isActivated: session.activationState == .activated,
            isPaired: session.isPaired,
            isCounterpartAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable
        )
        #else
        return LinkState(
            isActivated: session.activationState == .activated,
            isPaired: true,
            isCounterpartAppInstalled: session.isCompanionAppInstalled,
            isReachable: session.isReachable
        )
        #endif
    }

    public var receivedContext: WatchContext? {
        lock.lock(); defer { lock.unlock() }
        if let cached = _receivedContext { return cached }
        return WatchContext.from(session.receivedApplicationContext)
    }

    public func send(_ message: TransportMessage) throws {
        guard session.activationState == .activated else { throw TransportError.notActivated }
        session.transferUserInfo(try message.userInfo())
    }

    public func transferFile(_ url: URL, metadata: FileMetadata) throws {
        guard session.activationState == .activated else { throw TransportError.notActivated }
        session.transferFile(url, metadata: try metadata.dictionary())
    }

    public func cancelTransfers(docId: UUID) {
        for transfer in session.outstandingFileTransfers {
            if FileMetadata.from(transfer.file.metadata)?.docId == docId {
                transfer.cancel()
            }
        }
    }

    public func outstandingTransfers() -> [FileMetadata] {
        session.outstandingFileTransfers.compactMap { FileMetadata.from($0.file.metadata) }
    }

    public func updateContext(_ context: WatchContext) throws {
        guard session.activationState == .activated else { throw TransportError.notActivated }
        try session.updateApplicationContext(try context.dictionary())
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        continuation.yield(.stateChanged(state))
        if let context = WatchContext.from(session.receivedApplicationContext) {
            lock.lock(); _receivedContext = context; lock.unlock()
            continuation.yield(.context(context))
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
        continuation.yield(.stateChanged(state))
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: reactivate for the new one.
        session.activate()
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        continuation.yield(.stateChanged(state))
    }
    #else
    public func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        continuation.yield(.stateChanged(state))
    }
    #endif

    public func sessionReachabilityDidChange(_ session: WCSession) {
        continuation.yield(.stateChanged(state))
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let message = TransportMessage.from(userInfo: userInfo) {
            continuation.yield(.message(message))
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let context = WatchContext.from(applicationContext) {
            lock.lock(); _receivedContext = context; lock.unlock()
            continuation.yield(.context(context))
        }
    }

    /// The system deletes `file.fileURL` when this method returns, so the
    /// file is moved synchronously (WCH-01).
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = FileMetadata.from(file.metadata) else { return }
        let destination = stagingDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
            continuation.yield(.file(url: destination, metadata: metadata))
        } catch {
            // Ask for the file again.
            try? send(.resend(docId: metadata.docId, names: [metadata.name]))
        }
    }

    public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let metadata = FileMetadata.from(fileTransfer.file.metadata) else { return }
        continuation.yield(.fileTransferFinished(metadata: metadata, errorDescription: error?.localizedDescription))
    }
}
#endif
