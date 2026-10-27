import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import WatchDocsKit

/// File types accepted by `fileImporter` (IOS-01), from PRD section 3.
enum ImportTypes {
    static let all: [UTType] = {
        var types: [UTType] = [
            .pdf,
            .image, .jpeg, .png, .heic, .gif, .webP, .tiff, .bmp,
            .plainText, .utf8PlainText, .text, .json, .commaSeparatedText, .tabSeparatedText, .log, .xml, .yaml, .html,
            .rtf, .rtfd,
        ]
        let extra = ["docx", "doc", "xlsx", "xls", "md", "markdown", "odt", "pages", "numbers"]
        types += extra.compactMap { UTType(filenameExtension: $0) }
        return types
    }()

    /// Source type for a file URL, using the extension first, then the UTType.
    static func sourceType(for url: URL) -> SourceType? {
        if let type = SourceClassifier.sourceType(forExtension: url.pathExtension) { return type }
        guard let utType = UTType(filenameExtension: url.pathExtension) else { return nil }
        if utType.conforms(to: .pdf) { return .pdf }
        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .spreadsheet) { return .excel }
        if utType.conforms(to: .rtf) || utType.conforms(to: .rtfd) { return .word }
        if utType.conforms(to: .text) { return .text }
        return nil
    }
}

/// Photo picked with `PhotosPicker`, copied to a temporary file (IOS-02).
struct PickedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Photos", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "jpg" : received.file.pathExtension
            let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedPhoto(url: destination)
        }
    }
}
