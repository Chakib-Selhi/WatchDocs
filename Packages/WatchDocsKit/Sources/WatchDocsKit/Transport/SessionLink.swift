import Foundation

/// Events produced by a `SessionLink`.
public enum LinkEvent: Sendable {
    case message(TransportMessage)
    /// A file arrived. `url` is already outside the system's temporary inbox
    /// (the link moves it synchronously, as `WCSession` requires).
    case file(url: URL, metadata: FileMetadata)
    /// An outgoing file transfer ended. `errorDescription` is nil on success.
    case fileTransferFinished(metadata: FileMetadata, errorDescription: String?)
    case stateChanged(LinkState)
    case context(WatchContext)
}

/// Thin abstraction over `WCSession`, so the protocol logic can be tested
/// with an in-memory implementation (PRD 9.1).
public protocol SessionLink: Sendable {
    /// Single-consumer stream of incoming events.
    var incoming: AsyncStream<LinkEvent> { get }
    var state: LinkState { get }
    /// Last context received from the counterpart, if any.
    var receivedContext: WatchContext? { get }

    func activate()
    func send(_ message: TransportMessage) throws
    func transferFile(_ url: URL, metadata: FileMetadata) throws
    func cancelTransfers(docId: UUID)
    func outstandingTransfers() -> [FileMetadata]
    func updateContext(_ context: WatchContext) throws
}

public enum TransportError: Error, Equatable, Sendable {
    case notActivated
    case watchNotPaired
    case watchAppNotInstalled
    case insufficientWatchStorage(needed: Int64, available: Int64)
    case encodingFailed
}
