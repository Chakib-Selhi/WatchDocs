import Foundation
import ImageIO
import WatchDocsKit

/// Images and photos -> one resized page (HEIC). Animated GIF: first frame (V1).
enum ImageConverter {
    static func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> DocumentPackage {
        let format = ImageEncoder.effectiveFormat(request.options.format)
        let dir = request.outputDirectory
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(request.sourceURL as CFURL, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { throw ConversionError.unreadable }

        let maxPixels = request.options.quality.imageMaxDimension
        guard let image = ImageEncoder.downsample(source: source, maxPixelSize: maxPixels) else { throw ConversionError.unreadable }
        progress(0.5)

        let pageName = PackageNaming.pageFileName(index: 0, fileExtension: format.fileExtension)
        let pageURL = dir.appendingPathComponent(pageName)
        try ImageEncoder.write(image, to: pageURL, format: format, quality: request.options.quality.compression)
        var files: [(name: String, kind: FileKind)] = [(pageName, .page)]
        if let thumb = ImageEncoder.writeThumbnail(from: pageURL, into: dir, format: format) {
            files.append((thumb, .thumbnail))
        }
        progress(1)
        return try PackageBuilder.build(
            id: request.id,
            title: request.title,
            sourceType: request.sourceType,
            modes: [.pages],
            files: files,
            in: dir
        )
    }
}
