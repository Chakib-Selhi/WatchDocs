import Foundation
import WatchDocsKit

/// .txt, .md, .json, .log... -> UTF-8 text with encoding detection (M5).
enum TextConverter {
    static func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> DocumentPackage {
        guard let data = try? Data(contentsOf: request.sourceURL, options: .mappedIfSafe) else { throw ConversionError.unreadable }
        let text = decode(data)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConversionError.empty }
        try Data(text.utf8).write(to: request.outputDirectory.appendingPathComponent(PackageNaming.textFileName))
        progress(1)
        return try PackageBuilder.build(
            id: request.id,
            title: request.title,
            sourceType: .text,
            modes: [.text],
            files: [(PackageNaming.textFileName, .text)],
            in: request.outputDirectory
        )
    }

    static func decode(_ data: Data) -> String {
        TextDecoding.normalizeNewlines(TextDecoding.decode(data).text)
    }
}
