import Foundation
import WatchDocsKit

/// Input of a conversion.
struct ConversionRequest: Sendable {
    var id: UUID
    var sourceURL: URL
    var title: String
    var sourceType: SourceType
    var options: ConversionOptions
    var preferredMode: ReadingMode
    var password: String?
    /// Empty folder that receives the package files.
    var outputDirectory: URL
}

enum ConversionError: Error, Equatable {
    case unsupportedType
    case passwordRequired
    case wrongPassword
    case unreadable
    case empty
    case renderFailed
    case cancelled
}

extension ConversionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedType: String(localized: "This file type is not supported.")
        case .passwordRequired: String(localized: "This PDF is protected by a password.")
        case .wrongPassword: String(localized: "Wrong password.")
        case .unreadable: String(localized: "The file could not be read.")
        case .empty: String(localized: "The document is empty.")
        case .renderFailed: String(localized: "The layout of this document could not be rendered. Export it as PDF and try again.")
        case .cancelled: String(localized: "Conversion cancelled.")
        }
    }
}

typealias ProgressHandler = @Sendable (Double) -> Void

/// Picks the converter for a source type and builds the package.
enum DocumentConverter {
    static func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> DocumentPackage {
        try FileManager.default.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
        switch request.sourceType {
        case .pdf:
            return try await PDFConverter.convert(request, progress: progress)
        case .image, .photo:
            return try await ImageConverter.convert(request, progress: progress)
        case .text:
            return try await TextConverter.convert(request, progress: progress)
        case .word:
            return try await WordConverter.convert(request, progress: progress)
        case .excel:
            return try await ExcelConverter.convert(request, progress: progress)
        }
    }

    /// Orders modes so the user's preferred one comes first (the watch opens it by default).
    static func order(_ modes: [ReadingMode], preferred: ReadingMode) -> [ReadingMode] {
        var unique: [ReadingMode] = []
        for mode in modes where !unique.contains(mode) { unique.append(mode) }
        if let index = unique.firstIndex(of: preferred) {
            unique.remove(at: index)
            unique.insert(preferred, at: 0)
        }
        return unique
    }
}
