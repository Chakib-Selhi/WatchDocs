import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// "Send to Watch" in the share sheet (SHR-01, SHR-02).
///
/// WatchConnectivity is not available in extensions, so the shared files are
/// copied to the App Group inbox. The app converts and sends them as soon as it
/// runs (opened, notification tapped, or background task).
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.collect(from: items) }
    }
}

@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable {
        case working
        case done(count: Int)
        case nothingToSend
        case noAppGroup
    }

    var phase: Phase = .working

    /// Preferred types, most specific first.
    private let typeOrder: [UTType] = [.pdf, .image, .spreadsheet, .rtf, .plainText, .text, .data]

    func collect(from items: [NSExtensionItem]) async {
        guard AppGroup.isAvailable else {
            phase = .noAppGroup
            return
        }
        var count = 0
        for item in items {
            for provider in item.attachments ?? [] {
                if await save(provider) { count += 1 }
            }
        }
        if count > 0 {
            await notify(count: count)
            phase = .done(count: count)
        } else {
            phase = .nothingToSend
        }
    }

    /// Copies one attachment to the inbox. Files first, then images, then plain text.
    private func save(_ provider: NSItemProvider) async -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadFileURL(provider) {
            return (try? SharedInbox.add(fileAt: url)) != nil
        }
        for type in typeOrder where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if type == .plainText || type == .text, let text = await loadText(provider) {
                let name = (provider.suggestedName ?? "Note") + ".txt"
                return (try? SharedInbox.add(data: Data(text.utf8), name: name)) != nil
            }
            if let url = await loadFileRepresentation(provider, type: type) {
                return (try? SharedInbox.add(fileAt: url, preferredName: fileName(for: provider, type: type, url: url))) != nil
            }
        }
        return false
    }

    private func fileName(for provider: NSItemProvider, type: UTType, url: URL) -> String {
        let ext = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "dat") : url.pathExtension
        if let name = provider.suggestedName, !name.isEmpty {
            return name.hasSuffix("." + ext) ? name : name + "." + ext
        }
        return url.lastPathComponent
    }

    private func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    /// The provided file is deleted when the handler returns, so it is copied inside it.
    private func loadFileRepresentation(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
                let destination = copy.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// SHR-03: local notification, tapping it opens the app which sends the files.
    private func notify(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Ready to send")
        content.body = count == 1
            ? String(localized: "1 document is waiting. Tap to send it to your Apple Watch.")
            : String(localized: "\(count) documents are waiting. Tap to send them to your Apple Watch.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "inbox", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }
}

struct ShareView: View {
    let model: ShareModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch model.phase {
            case .working:
                ProgressView()
                Text("Preparing…")
            case .done(let count):
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text(count == 1 ? "1 document added" : "\(count) documents added")
                    .font(.headline)
                Text("Open WatchDocs (or tap the notification) to convert and send to your Apple Watch.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            case .nothingToSend:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Nothing to send")
                    .font(.headline)
                Text("WatchDocs accepts PDFs, images, Word, Excel and text files.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            case .noAppGroup:
                Image(systemName: "xmark.octagon")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                Text("App Group not configured")
                    .font(.headline)
                Text("Enable the App Group capability for the app and the extension in Xcode.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if model.phase != .working {
                Button("Done", action: close)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
