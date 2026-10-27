import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WatchDocsKit

/// Writes CGImages as HEIC (default) or JPEG, and downsamples images with ImageIO.
enum ImageEncoder {
    static let thumbnailMaxPixels = 240

    static var supportsHEIC: Bool {
        let types = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return types.contains(UTType.heic.identifier)
    }

    /// Format actually used: HEIC falls back to JPEG on devices that cannot encode it.
    static func effectiveFormat(_ requested: PageImageFormat) -> PageImageFormat {
        requested == .heic && !supportsHEIC ? .jpeg : requested
    }

    /// Encodes `image` to `url`. If HEIC encoding fails, JPEG data is written
    /// instead (ImageIO on the watch detects the real format from the content).
    static func write(_ image: CGImage, to url: URL, format: PageImageFormat, quality: Double) throws {
        if format == .heic, encode(image, to: url, type: .heic, quality: quality) { return }
        guard encode(image, to: url, type: .jpeg, quality: quality) else { throw ConversionError.renderFailed }
    }

    private static func encode(_ image: CGImage, to url: URL, type: UTType, quality: Double) -> Bool {
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Downsampled, orientation-corrected image (memory friendly: never decodes the full image).
    static func downsample(source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func downsample(url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }

    /// Writes a small thumbnail next to the pages.
    static func writeThumbnail(from imageURL: URL, into directory: URL, format: PageImageFormat) -> String? {
        guard let thumb = downsample(url: imageURL, maxPixelSize: thumbnailMaxPixels) else { return nil }
        let name = PackageNaming.thumbnailFileName(fileExtension: format.fileExtension)
        do {
            try write(thumb, to: directory.appendingPathComponent(name), format: format, quality: 0.6)
            return name
        } catch {
            return nil
        }
    }

    /// Opaque white RGB bitmap context of the given pixel size.
    static func makeWhiteContext(width: Int, height: Int) -> CGContext? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        return context
    }
}
