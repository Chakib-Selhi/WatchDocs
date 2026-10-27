import Foundation
import Observation
import SwiftData
import WatchDocsKit

/// Import -> conversion -> preview -> send -> delivery tracking.
/// Conversions run one at a time in the background (PRD section 7), so the
/// number of documents and pages is not limited by memory.
@MainActor
@Observable
final class DocumentPipeline {
    struct PasswordPrompt: Identifiable {
        let id: UUID
        let title: String
        var wrongPassword: Bool
    }

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private struct Job {
        let documentId: UUID
        let fileURL: URL
        let title: String
        let sourceType: SourceType
        let autoSend: Bool
        var password: String?
    }

    let settings: AppSettings
    private let transport: DocumentTransport
    private let context: ModelContext

    private(set) var linkState: LinkState
    private(set) var watchContext: WatchContext?

    private var jobs: [Job] = []
    private var jobsAwaitingPassword: [UUID: Job] = [:]
    private(set) var currentTitle: String?
    private(set) var currentProgress: Double = 0
    private var worker: Task<Void, Never>?
    private var progressTimer: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?

    /// Documents converted in the last batch, shown in the preview sheet.
    var previewIDs: [UUID] = []
    var passwordPrompt: PasswordPrompt?
    var alert: AlertMessage?

    var isConverting: Bool { currentTitle != nil || !jobs.isEmpty }
    var queuedConversions: Int { jobs.count }

    init(settings: AppSettings, transport: DocumentTransport, context: ModelContext) {
        self.settings = settings
        self.transport = transport
        self.context = context
        self.linkState = transport.linkState
        self.watchContext = transport.watchContext
        StoragePaths.prepare()
        recoverInterruptedWork()
        eventsTask = Task { [weak self] in
            guard let events = self?.transport.events else { return }
            for await event in events {
                self?.handle(event)
            }
        }
        startProgressTimer()
    }

    // MARK: Import

    /// Imports files from the Files app or the share inbox.
    func importFiles(_ urls: [URL], fromShareSheet: Bool = false) {
        var unsupported: [String] = []
        for url in urls {
            guard let type = ImportTypes.sourceType(for: url) else {
                unsupported.append(url.lastPathComponent)
                continue
            }
            do {
                let local = try StoragePaths.copyToImports(url)
                enqueue(fileURL: local, originalName: url.lastPathComponent, sourceType: type, fromShareSheet: fromShareSheet)
            } catch {
                unsupported.append(url.lastPathComponent)
            }
        }
        if !unsupported.isEmpty {
            alert = AlertMessage(
                title: String(localized: "Some files were not imported"),
                message: unsupported.joined(separator: "\n")
            )
        }
    }

    /// Imports photos already copied to temporary files (PhotosPicker).
    func importPhotos(_ urls: [URL]) {
        for (index, url) in urls.enumerated() {
            guard let local = try? StoragePaths.copyToImports(url) else { continue }
            try? FileManager.default.removeItem(at: url)
            let name = urls.count > 1
                ? String(localized: "Photo \(index + 1)")
                : String(localized: "Photo")
            enqueue(fileURL: local, originalName: name, sourceType: .photo, fromShareSheet: false, title: name)
        }
    }

    /// Converts and sends what the share extension dropped in the App Group (SHR-02).
    func processInbox() {
        let files = SharedInbox.pendingFiles()
        guard !files.isEmpty else { return }
        for file in files {
            if let type = ImportTypes.sourceType(for: file), let local = try? StoragePaths.copyToImports(file) {
                enqueue(fileURL: local, originalName: file.lastPathComponent, sourceType: type, fromShareSheet: true)
            }
            SharedInbox.remove(file)
        }
    }

    private func enqueue(fileURL: URL, originalName: String, sourceType: SourceType, fromShareSheet: Bool, title: String? = nil) {
        let title = title ?? SourceClassifier.title(forFileName: originalName)
        let document = SentDocument(title: title, sourceType: sourceType, originalFileName: originalName, fromShareSheet: fromShareSheet)
        document.importPath = fileURL.path
        context.insert(document)
        save()
        let autoSend = fromShareSheet ? settings.autoSendShared : !settings.previewBeforeSend
        jobs.append(Job(documentId: document.id, fileURL: fileURL, title: title, sourceType: sourceType, autoSend: autoSend, password: nil))
        startWorker()
    }

    // MARK: Conversion

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, !self.jobs.isEmpty {
                let job = self.jobs.removeFirst()
                await self.run(job)
            }
            self?.worker = nil
            self?.currentTitle = nil
        }
    }

    private func run(_ job: Job) async {
        guard let document = fetch(job.documentId) else { return }
        currentTitle = job.title
        currentProgress = 0
        document.status = .converting
        document.failureReason = nil
        save()

        let output = StoragePaths.package(for: job.documentId)
        try? FileManager.default.removeItem(at: output)
        let request = ConversionRequest(
            id: job.documentId,
            sourceURL: job.fileURL,
            title: job.title,
            sourceType: job.sourceType,
            options: settings.conversionOptions,
            preferredMode: settings.preferredMode,
            password: job.password,
            outputDirectory: output
        )
        do {
            let package = try await Task.detached(priority: .userInitiated) {
                try await DocumentConverter.convert(request) { value in
                    Task { @MainActor [weak self] in self?.currentProgress = value }
                }
            }.value
            guard let document = fetch(job.documentId) else {
                try? FileManager.default.removeItem(at: output)
                return
            }
            document.apply(package.manifest)
            document.title = package.manifest.title
            document.status = .ready
            StoragePaths.removeImport(document.importPath)
            document.importPath = nil
            save()
            if job.autoSend {
                send(document)
            } else {
                previewIDs.append(document.id)
            }
        } catch let error as ConversionError where error == .passwordRequired || error == .wrongPassword {
            try? FileManager.default.removeItem(at: output)
            jobsAwaitingPassword[job.documentId] = job
            document.fail(error.localizedDescription)
            save()
            passwordPrompt = PasswordPrompt(id: job.documentId, title: job.title, wrongPassword: error == .wrongPassword)
        } catch {
            try? FileManager.default.removeItem(at: output)
            fetch(job.documentId)?.fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            save()
        }
        currentTitle = nil
    }

    func submitPassword(_ password: String, for id: UUID) {
        passwordPrompt = nil
        guard var job = jobsAwaitingPassword.removeValue(forKey: id) else { return }
        job.password = password
        jobs.append(job)
        startWorker()
    }

    func cancelPassword(for id: UUID) {
        passwordPrompt = nil
        jobsAwaitingPassword[id] = nil
    }

    // MARK: Sending

    func send(_ document: SentDocument) {
        let directory = StoragePaths.package(for: document.id)
        guard let package = try? DocumentPackage.load(from: directory), package.allFilesPresent() else {
            retryConversionOrFail(document)
            return
        }
        do {
            try PhoneTransport.checkStorage(packageBytes: package.manifest.totalBytes, context: watchContext, userLimit: settings.storageLimitBytes)
        } catch {
            document.fail(message(for: error))
            save()
            return
        }
        document.status = linkState.isReachable ? .sending : .queued
        document.progress = 0
        document.failureReason = nil
        save()
        Task {
            do {
                try await transport.send(package)
            } catch {
                fetch(document.id)?.fail(message(for: error))
                save()
            }
        }
    }

    func sendAll(_ ids: [UUID]) {
        for id in ids {
            if let document = fetch(id), document.status == .ready { send(document) }
        }
        previewIDs.removeAll { ids.contains($0) }
    }

    /// IOS-09: resend without converting again when the package still exists.
    func retry(_ document: SentDocument) {
        if FileManager.default.fileExists(atPath: StoragePaths.package(for: document.id).appendingPathComponent(DocumentManifest.fileName).path) {
            send(document)
        } else {
            retryConversionOrFail(document)
        }
    }

    private func retryConversionOrFail(_ document: SentDocument) {
        if let path = document.importPath, FileManager.default.fileExists(atPath: path) {
            jobs.append(Job(documentId: document.id, fileURL: URL(fileURLWithPath: path), title: document.title,
                            sourceType: document.sourceType, autoSend: true, password: nil))
            startWorker()
        } else {
            document.fail(String(localized: "The converted file is no longer available. Import the document again."))
            save()
        }
    }

    // MARK: Library actions

    func delete(_ document: SentDocument) {
        let id = document.id
        StoragePaths.removeImport(document.importPath)
        try? FileManager.default.removeItem(at: StoragePaths.package(for: id))
        jobs.removeAll { $0.documentId == id }
        previewIDs.removeAll { $0 == id }
        context.delete(document)
        save()
        Task { try? await transport.delete(documentId: id) }
    }

    func rename(_ document: SentDocument, to newTitle: String) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != document.title else { return }
        document.title = title
        save()
        let directory = StoragePaths.package(for: document.id)
        if var package = try? DocumentPackage.load(from: directory) {
            package.manifest.title = title
            try? package.saveManifest()
        }
        if document.status == .delivered || document.status == .sending || document.status == .queued {
            let id = document.id
            Task { try? await transport.rename(documentId: id, title: title) }
        }
    }

    func discardPreview() {
        previewIDs.removeAll()
    }

    // MARK: Transport events

    private func handle(_ event: TransportEvent) {
        switch event {
        case .delivered(let id):
            guard let document = fetch(id) else { return }
            document.status = .delivered
            document.progress = 1
            document.failureReason = nil
            try? FileManager.default.removeItem(at: StoragePaths.package(for: id))
            save()
        case .deletedOnWatch(let id):
            guard let document = fetch(id) else { return }
            try? FileManager.default.removeItem(at: StoragePaths.package(for: id))
            context.delete(document)
            save()
        case .fileSent(let id, _):
            if let document = fetch(id), document.status == .queued {
                document.status = .sending
            }
        case .fileFailed(let id, _, let reason):
            guard let document = fetch(id), document.status == .sending || document.status == .queued else { return }
            document.fail(reason)
            save()
        case .resendRequested(let id, let names):
            guard let package = try? DocumentPackage.load(from: StoragePaths.package(for: id)) else { return }
            Task { try? await transport.resend(package, names: names) }
        case .linkStateChanged(let state):
            linkState = state
            if state.isReachable {
                for document in documents(with: .queued) { document.status = .sending }
                save()
            }
        case .watchContextChanged(let watchContext):
            self.watchContext = watchContext
        }
    }

    private func startProgressTimer() {
        progressTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.refreshProgress()
            }
        }
    }

    private func refreshProgress() async {
        linkState = transport.linkState
        let active = documents(with: .sending) + documents(with: .queued)
        for document in active {
            let value = await transport.progress(for: document.id, totalFiles: document.fileCount)
            // nil: every file was handed over, waiting for the watch confirmation.
            document.progress = value ?? 1
        }
    }

    // MARK: Startup recovery

    private func recoverInterruptedWork() {
        for document in documents(with: .converting) {
            if let path = document.importPath, FileManager.default.fileExists(atPath: path) {
                jobs.append(Job(documentId: document.id, fileURL: URL(fileURLWithPath: path), title: document.title,
                                sourceType: document.sourceType, autoSend: document.fromShareSheet && settings.autoSendShared, password: nil))
            } else {
                document.fail(String(localized: "Conversion was interrupted. Import the document again."))
            }
        }
        save()
        if !jobs.isEmpty { startWorker() }
    }

    // MARK: Helpers

    func fetch(_ id: UUID) -> SentDocument? {
        var descriptor = FetchDescriptor<SentDocument>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func documents(with status: DeliveryStatus) -> [SentDocument] {
        let raw = status.rawValue
        let descriptor = FetchDescriptor<SentDocument>(predicate: #Predicate { $0.statusRaw == raw })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        try? context.save()
    }

    func message(for error: Error) -> String {
        switch error {
        case TransportError.notActivated:
            return String(localized: "The connection with the watch is not ready yet. Try again in a moment.")
        case TransportError.watchNotPaired:
            return String(localized: "No Apple Watch is paired with this iPhone.")
        case TransportError.watchAppNotInstalled:
            return String(localized: "WatchDocs is not installed on the watch. Install it from the Watch app on the iPhone.")
        case TransportError.insufficientWatchStorage(let needed, let available):
            return String(localized: "Not enough space on the watch: \(ByteFormatting.string(needed)) needed, \(ByteFormatting.string(available)) available. Delete documents on the watch or choose the Economy quality.")
        default:
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
