import Foundation

/// Paths and defaults shared by the iOS app and the share extension.
enum AppGroup {
    /// Read from Info.plist (`WDAppGroup`), itself built from `BUNDLE_PREFIX` in project.yml.
    static let identifier: String = {
        (Bundle.main.object(forInfoDictionaryKey: "WDAppGroup") as? String) ?? "group.com.example.watchdocs"
    }()

    /// Shared container, or the app's own Application Support if the
    /// App Group is not provisioned (the share extension then cannot hand files over).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    /// Files dropped by the share extension, one sub folder per shared file.
    static var inboxURL: URL {
        containerURL.appendingPathComponent("Inbox", isDirectory: true)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Keys of the shared settings.
enum SettingsKey {
    static let quality = "quality"
    static let imageFormat = "imageFormat"
    static let preferredMode = "preferredMode"
    static let storageLimitMB = "storageLimitMB"
    static let autoSendShared = "autoSendShared"
    static let previewBeforeSend = "previewBeforeSend"
}

/// Inbox layout: `Inbox/<uuid>/<original file name>`.
enum SharedInbox {
    /// Copies a file into the inbox. Used by the share extension.
    @discardableResult
    static func add(fileAt source: URL, preferredName: String? = nil) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = AppGroup.inboxURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = sanitize(preferredName ?? source.lastPathComponent)
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func add(data: Data, name: String) throws {
        let folder = AppGroup.inboxURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(sanitize(name)))
    }

    /// Files waiting in the inbox, oldest first.
    static func pendingFiles() -> [URL] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: AppGroup.inboxURL, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        let sorted = folders.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        return sorted.compactMap { folder in
            (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.first
        }
    }

    static var isEmpty: Bool { pendingFiles().isEmpty }

    /// Removes the inbox folder that holds `file`.
    static func remove(_ file: URL) {
        let folder = file.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL == AppGroup.inboxURL.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "file" + cleaned : cleaned
    }
}
