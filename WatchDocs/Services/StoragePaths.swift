import Foundation

/// Folders used by the iOS app.
enum StoragePaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WatchDocs", isDirectory: true)
    }

    /// Converted packages, kept until the watch confirms reception (retry without reconverting, IOS-09).
    static var outbox: URL { root.appendingPathComponent("Outbox", isDirectory: true) }

    /// Copies of imported files, kept until their conversion succeeds.
    static var imports: URL { root.appendingPathComponent("Imports", isDirectory: true) }

    /// Files received through WatchConnectivity (unused on iOS in V1, required by the link).
    static var staging: URL { root.appendingPathComponent("Staging", isDirectory: true) }

    static func package(for id: UUID) -> URL {
        outbox.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func prepare() {
        let fm = FileManager.default
        for dir in [outbox, imports, staging] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
    }

    /// Copies an imported file (security scoped or from the inbox) into `Imports/<uuid>/`.
    static func copyToImports(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = imports.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        // Coordinated read: files from iCloud Drive may need downloading first.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = copyError ?? coordinationError { throw error }
        return destination
    }

    static func removeImport(_ path: String?) {
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
