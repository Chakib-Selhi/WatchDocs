import Foundation

/// Small control messages sent with `transferUserInfo` (queued, guaranteed delivery).
public enum TransportMessage: Codable, Sendable, Equatable {
    /// Watch -> iPhone: every file of the document arrived and was verified.
    case ack(docId: UUID)
    /// Either direction: the document was deleted on the sender side.
    case delete(docId: UUID)
    /// iPhone -> watch: the user renamed a document.
    case rename(docId: UUID, title: String)
    /// Watch -> iPhone: a file failed verification; the iPhone resends it.
    case resend(docId: UUID, names: [String])

    public static let userInfoKey = "wd"

    public func userInfo() throws -> [String: Data] {
        [Self.userInfoKey: try JSONCoding.encoder.encode(self)]
    }

    public static func from(userInfo: [String: Any]) -> TransportMessage? {
        guard let data = userInfo[userInfoKey] as? Data else { return nil }
        return try? JSONCoding.decoder.decode(TransportMessage.self, from: data)
    }
}

/// Metadata attached to every `transferFile`. The PRD's `["docId", "name", "index"]`
/// plus the kind, so the manifest can travel as a file as well.
public struct FileMetadata: Codable, Sendable, Hashable {
    public let docId: UUID
    public let name: String
    public let kind: FileKind
    public let index: Int

    public init(docId: UUID, name: String, kind: FileKind, index: Int) {
        self.docId = docId
        self.name = name
        self.kind = kind
        self.index = index
    }

    public func dictionary() throws -> [String: Data] {
        [TransportMessage.userInfoKey: try JSONCoding.encoder.encode(self)]
    }

    public static func from(_ dictionary: [String: Any]?) -> FileMetadata? {
        guard let data = dictionary?[TransportMessage.userInfoKey] as? Data else { return nil }
        return try? JSONCoding.decoder.decode(FileMetadata.self, from: data)
    }
}

/// Watch -> iPhone status published with `updateApplicationContext`.
public struct WatchContext: Codable, Sendable, Equatable {
    public var documentCount: Int
    public var usedBytes: Int64
    /// Free space reported by the watch volume, or nil if unknown.
    public var freeBytes: Int64?
    public var updatedAt: Date

    public init(documentCount: Int, usedBytes: Int64, freeBytes: Int64?, updatedAt: Date = Date()) {
        self.documentCount = documentCount
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.updatedAt = updatedAt
    }

    public func dictionary() throws -> [String: Data] {
        [TransportMessage.userInfoKey: try JSONCoding.encoder.encode(self)]
    }

    public static func from(_ dictionary: [String: Any]) -> WatchContext? {
        guard let data = dictionary[TransportMessage.userInfoKey] as? Data else { return nil }
        return try? JSONCoding.decoder.decode(WatchContext.self, from: data)
    }
}

/// Connection state of the counterpart device.
public struct LinkState: Sendable, Equatable {
    public var isActivated: Bool
    public var isPaired: Bool
    public var isCounterpartAppInstalled: Bool
    public var isReachable: Bool

    public init(isActivated: Bool = false, isPaired: Bool = false, isCounterpartAppInstalled: Bool = false, isReachable: Bool = false) {
        self.isActivated = isActivated
        self.isPaired = isPaired
        self.isCounterpartAppInstalled = isCounterpartAppInstalled
        self.isReachable = isReachable
    }
}
