import Foundation
import SwiftData
import WatchDocsKit

/// Status of a document on the iPhone side (IOS-05).
enum DeliveryStatus: String, Codable, CaseIterable {
    /// Being converted.
    case converting
    /// Converted, waiting for the user to confirm the send (preview).
    case ready
    /// Handed to WatchConnectivity, watch not reachable: delivered later automatically.
    case queued
    /// Transfer in progress.
    case sending
    /// The watch confirmed reception of every file.
    case delivered
    case failed
}

/// Reference list of documents, kept on the iPhone (PRD 4, "Synchronisation des métadonnées").
@Model
final class SentDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceTypeRaw: String
    var originalFileName: String
    var createdAt: Date
    var statusRaw: String
    var failureReason: String?
    var pageCount: Int
    var totalBytes: Int64
    var fileCount: Int
    var modesRaw: [String]
    /// 0...1 while sending.
    var progress: Double
    /// True when the file came from the share sheet (auto send).
    var fromShareSheet: Bool
    /// Copy of the original file kept until conversion succeeds (allows retrying an interrupted conversion).
    var importPath: String?

    init(id: UUID = UUID(), title: String, sourceType: SourceType, originalFileName: String, fromShareSheet: Bool = false) {
        self.id = id
        self.title = title
        self.sourceTypeRaw = sourceType.rawValue
        self.originalFileName = originalFileName
        self.createdAt = Date()
        self.statusRaw = DeliveryStatus.converting.rawValue
        self.failureReason = nil
        self.pageCount = 0
        self.totalBytes = 0
        self.fileCount = 0
        self.modesRaw = []
        self.progress = 0
        self.fromShareSheet = fromShareSheet
    }

    var status: DeliveryStatus {
        get { DeliveryStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var sourceType: SourceType { SourceType(rawValue: sourceTypeRaw) ?? .pdf }
    var modes: [ReadingMode] { modesRaw.compactMap(ReadingMode.init(rawValue:)) }

    func apply(_ manifest: DocumentManifest) {
        pageCount = manifest.pageCount
        totalBytes = manifest.totalBytes
        fileCount = manifest.files.count
        modesRaw = manifest.modes.map(\.rawValue)
    }

    func fail(_ reason: String) {
        status = .failed
        failureReason = reason
        progress = 0
    }
}
