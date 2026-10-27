import Foundation

/// Rasterization quality (PRD section 3, IOS-08).
public enum ConversionQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case economy, standard, high

    public var id: String { rawValue }

    /// Width in pixels of rasterized pages.
    public var pageWidth: Int {
        switch self {
        case .economy: 500
        case .standard: 800
        case .high: 1200
        }
    }

    /// Longest side for photos and images (taller than pages to keep QR codes legible).
    public var imageMaxDimension: Int { pageWidth * 2 }

    public var compression: Double {
        switch self {
        case .economy: 0.55
        case .standard: 0.7
        case .high: 0.8
        }
    }
}

public enum PageImageFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case heic, jpeg
    public var id: String { rawValue }
    public var fileExtension: String { self == .heic ? "heic" : "jpg" }
}

public struct ConversionOptions: Sendable, Equatable {
    public var quality: ConversionQuality
    public var format: PageImageFormat
    /// Number of pages rendered before yielding, to bound memory (PRD section 7).
    public var batchSize: Int

    public init(quality: ConversionQuality = .standard, format: PageImageFormat = .heic, batchSize: Int = 5) {
        self.quality = quality
        self.format = format
        self.batchSize = batchSize
    }
}

/// Maps file extensions to source types (PRD section 3).
public enum SourceClassifier {
    public static func sourceType(forExtension ext: String) -> SourceType? {
        switch ext.lowercased() {
        case "pdf": .pdf
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp": .image
        case "docx", "doc", "rtf", "rtfd", "odt", "pages": .word
        case "xlsx", "xls", "csv", "tsv", "numbers": .excel
        case "txt", "text", "md", "markdown", "json", "log", "xml", "yaml", "yml", "html", "htm": .text
        default: nil
        }
    }

    /// Title from a file name, without extension.
    public static func title(forFileName name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? name : base
    }
}

/// Human readable byte counts (ByteCountFormatter is not on every platform the tests run on).
public enum ByteFormatting {
    public static func string(_ bytes: Int64) -> String {
        #if canImport(Darwin)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        #else
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return unit == 0 ? "\(bytes) B" : "\(String(format: "%.1f", value)) \(units[unit])"
        #endif
    }
}
