import Foundation
import Observation
import WatchDocsKit

/// User settings (IOS-08), stored in the App Group defaults.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var quality: ConversionQuality {
        didSet { defaults.set(quality.rawValue, forKey: SettingsKey.quality) }
    }

    var imageFormat: PageImageFormat {
        didSet { defaults.set(imageFormat.rawValue, forKey: SettingsKey.imageFormat) }
    }

    /// Mode shown first on the watch when a document has several.
    var preferredMode: ReadingMode {
        didSet { defaults.set(preferredMode.rawValue, forKey: SettingsKey.preferredMode) }
    }

    /// Optional cap on the space WatchDocs may use on the watch. 0 = no limit
    /// (only the free space of the watch matters).
    var storageLimitMB: Int {
        didSet { defaults.set(storageLimitMB, forKey: SettingsKey.storageLimitMB) }
    }

    /// Files shared from other apps are sent without the preview step.
    var autoSendShared: Bool {
        didSet { defaults.set(autoSendShared, forKey: SettingsKey.autoSendShared) }
    }

    /// Show the preview (title, pages, size) before sending files imported in the app (IOS-04).
    var previewBeforeSend: Bool {
        didSet { defaults.set(previewBeforeSend, forKey: SettingsKey.previewBeforeSend) }
    }

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            SettingsKey.quality: ConversionQuality.standard.rawValue,
            SettingsKey.imageFormat: PageImageFormat.heic.rawValue,
            SettingsKey.preferredMode: ReadingMode.pages.rawValue,
            SettingsKey.storageLimitMB: 0,
            SettingsKey.autoSendShared: true,
            SettingsKey.previewBeforeSend: true,
        ])
        quality = ConversionQuality(rawValue: defaults.string(forKey: SettingsKey.quality) ?? "") ?? .standard
        imageFormat = PageImageFormat(rawValue: defaults.string(forKey: SettingsKey.imageFormat) ?? "") ?? .heic
        preferredMode = ReadingMode(rawValue: defaults.string(forKey: SettingsKey.preferredMode) ?? "") ?? .pages
        storageLimitMB = defaults.integer(forKey: SettingsKey.storageLimitMB)
        autoSendShared = defaults.bool(forKey: SettingsKey.autoSendShared)
        previewBeforeSend = defaults.bool(forKey: SettingsKey.previewBeforeSend)
    }

    var conversionOptions: ConversionOptions {
        ConversionOptions(quality: quality, format: imageFormat)
    }

    var storageLimitBytes: Int64? {
        storageLimitMB > 0 ? Int64(storageLimitMB) * 1_000_000 : nil
    }

    static let storageLimitChoices: [Int] = [0, 250, 500, 1000, 2000, 4000, 8000]
}
