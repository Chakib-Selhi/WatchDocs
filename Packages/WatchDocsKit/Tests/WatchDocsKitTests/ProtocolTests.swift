import Foundation
import Testing
@testable import WatchDocsKit

/// Integration tests of the transfer protocol (PRD 9.2) with an in-memory link:
/// random arrival order, duplicates, missing files, corruption, deletion.
@Suite("Transfer protocol")
struct ProtocolTests {
    // MARK: Assembler only

    private func feed(_ package: DocumentPackage, to assembler: DocumentAssembler, staging: URL, order: [PackageFile]? = nil, manifestPosition: Int = 0) async throws -> [DocumentAssembler.Outcome] {
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var items: [(URL, FileMetadata)] = []
        for (i, file) in (order ?? package.transferOrder).enumerated() {
            let copy = staging.appendingPathComponent(UUID().uuidString)
            try fm.copyItem(at: package.url(for: file), to: copy)
            items.append((copy, FileMetadata(docId: package.manifest.id, name: file.name, kind: file.kind, index: i)))
        }
        let manifestCopy = staging.appendingPathComponent(UUID().uuidString)
        try fm.copyItem(at: package.manifestURL, to: manifestCopy)
        let manifestItem = (manifestCopy, FileMetadata(docId: package.manifest.id, name: DocumentManifest.fileName, kind: .manifest, index: -1))
        items.insert(manifestItem, at: min(manifestPosition, items.count))
        var outcomes: [DocumentAssembler.Outcome] = []
        for (url, meta) in items {
            outcomes.append(await assembler.receive(fileAt: url, metadata: meta))
        }
        return outcomes
    }

    @Test func completesInOrder() async throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 12, in: root)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let assembler = DocumentAssembler(store: store)
        let outcomes = try await feed(package, to: assembler, staging: root.appendingPathComponent("s"))
        #expect(outcomes.last == .completed(docId: package.manifest.id))
        #expect(outcomes.dropLast().allSatisfy { $0 == .progress(docId: package.manifest.id) })
        let docs = store.listDocuments()
        #expect(docs.count == 1)
        #expect(docs[0].isComplete)
        #expect(docs[0].manifest.pageCount == 12)
    }

    @Test func completesWhenManifestArrivesLastAndOrderIsRandom() async throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 30, in: root)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let assembler = DocumentAssembler(store: store)
        let outcomes = try await feed(package, to: assembler, staging: root.appendingPathComponent("s"),
                                      order: package.transferOrder.shuffled(), manifestPosition: Int.max)
        #expect(outcomes.last == .completed(docId: package.manifest.id))
        #expect(store.isComplete(package.manifest.id))
        #expect(!FileManager.default.fileExists(atPath: store.pendingDirectory(for: package.manifest.id).path))
    }

    @Test func incompleteDocumentIsNeverReady() async throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 5, in: root)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let assembler = DocumentAssembler(store: store)
        let partial = Array(package.transferOrder.dropLast())
        let outcomes = try await feed(package, to: assembler, staging: root.appendingPathComponent("s"), order: partial)
        #expect(!outcomes.contains(.completed(docId: package.manifest.id)))
        let doc = try #require(store.listDocuments().first)
        #expect(!doc.isComplete)
        #expect(doc.receivedFiles == package.manifest.files.count - 1)
    }

    @Test func duplicatesAreHarmless() async throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 4, in: root)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let assembler = DocumentAssembler(store: store)
        let doubled = package.transferOrder + package.transferOrder
        let outcomes = try await feed(package, to: assembler, staging: root.appendingPathComponent("s"), order: doubled)
        #expect(outcomes.contains(.completed(docId: package.manifest.id)))
        #expect(store.isComplete(package.manifest.id))
        // Re-sending the manifest of a complete document re-confirms it.
        let again = try await feed(package, to: assembler, staging: root.appendingPathComponent("s2"), order: [])
        #expect(again == [.completed(docId: package.manifest.id)])
    }

    @Test func corruptedFileIsRejectedThenAccepted() async throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 3, in: root)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let assembler = DocumentAssembler(store: store)
        let target = package.manifest.pageFiles[1]
        let staging = root.appendingPathComponent("s")
        _ = try await feed(package, to: assembler, staging: staging, order: package.transferOrder.filter { $0 != target })

        // Same size, different content.
        let bad = staging.appendingPathComponent("bad")
        try Data(count: Int(target.bytes)).write(to: bad)
        let meta = FileMetadata(docId: package.manifest.id, name: target.name, kind: .page, index: 0)
        #expect(await assembler.receive(fileAt: bad, metadata: meta) == .rejected(docId: package.manifest.id, names: [target.name]))
        #expect(!store.isComplete(package.manifest.id))

        let good = staging.appendingPathComponent("good")
        try FileManager.default.copyItem(at: package.url(for: target), to: good)
        #expect(await assembler.receive(fileAt: good, metadata: meta) == .completed(docId: package.manifest.id))
    }

    @Test func deletionDiscardsLateFiles() async throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 3, in: root)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let assembler = DocumentAssembler(store: store)
        let staging = root.appendingPathComponent("s")
        _ = try await feed(package, to: assembler, staging: staging, order: Array(package.transferOrder.prefix(2)))
        await assembler.delete(docId: package.manifest.id)
        #expect(store.listDocuments().isEmpty)
        let late = try await feed(package, to: assembler, staging: staging, order: Array(package.transferOrder.dropFirst(2)))
        #expect(late.allSatisfy { $0 == .ignored })
        #expect(store.listDocuments().isEmpty)
        // Tombstones survive a restart.
        let reopened = DocumentAssembler(store: store)
        #expect(await reopened.isDeleted(package.manifest.id))
    }

    @Test func renameUpdatesManifest() async throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 1, in: root)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let assembler = DocumentAssembler(store: store)
        _ = try await feed(package, to: assembler, staging: root.appendingPathComponent("s"))
        await assembler.rename(docId: package.manifest.id, title: "Nouveau titre")
        #expect(store.manifest(for: package.manifest.id)?.title == "Nouveau titre")
    }

    @Test func noPageLimit() async throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 1_500, in: root, pageBytes: 16)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let assembler = DocumentAssembler(store: store)
        let outcomes = try await feed(package, to: assembler, staging: root.appendingPathComponent("s"), order: package.transferOrder.shuffled())
        #expect(outcomes.last == .completed(docId: package.manifest.id))
        #expect(store.document(id: package.manifest.id)?.manifest.pageCount == 1_500)
    }

    // MARK: End to end with transports

    private func waitFor(_ timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    final class EventLog<E: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [E] = []
        func append(_ e: E) { lock.lock(); items.append(e); lock.unlock() }
        var all: [E] { lock.lock(); defer { lock.unlock() }; return items }
    }

    @Test func endToEndDeliveryWithRandomOrderAndDuplicates() async throws {
        let root = TestFiles.makeTempDir()
        let (phoneLink, watchLink) = InMemoryLink.pair(root: root)
        let phone = PhoneTransport(link: phoneLink)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let receiver = WatchReceiver(link: watchLink, store: store)

        let phoneEvents = EventLog<TransportEvent>()
        let phoneTask = Task { for await e in phone.events { phoneEvents.append(e) } }
        let watchEvents = EventLog<WatchReceiver.Event>()
        let watchTask = Task { for await e in receiver.events { watchEvents.append(e) } }
        defer { phoneTask.cancel(); watchTask.cancel() }

        let package = try TestFiles.makePackage(pages: 20, in: root)
        try await phone.send(package)
        #expect(await phone.progress(for: package.manifest.id, totalFiles: package.manifest.files.count) == 0)

        phoneLink.deliver(shuffled: true, duplicateFiles: true)
        let completed = await waitFor { watchEvents.all.contains(.documentCompleted(package.manifest.id)) }
        #expect(completed)

        // The watch acknowledges, the iPhone sees "delivered".
        watchLink.deliver()
        let delivered = await waitFor { phoneEvents.all.contains(.delivered(docId: package.manifest.id)) }
        #expect(delivered)
        #expect(phoneLink.receivedContext?.documentCount == 1)
        #expect(await phone.progress(for: package.manifest.id, totalFiles: package.manifest.files.count) == nil)
        _ = receiver
    }

    @Test func deletionPropagatesBothWays() async throws {
        let root = TestFiles.makeTempDir()
        let (phoneLink, watchLink) = InMemoryLink.pair(root: root)
        let phone = PhoneTransport(link: phoneLink)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let receiver = WatchReceiver(link: watchLink, store: store)
        let phoneEvents = EventLog<TransportEvent>()
        let phoneTask = Task { for await e in phone.events { phoneEvents.append(e) } }
        defer { phoneTask.cancel() }

        let a = try TestFiles.makePackage(pages: 2, in: root, title: "A")
        let b = try TestFiles.makePackage(pages: 2, in: root, title: "B")
        try await phone.send(a)
        try await phone.send(b)
        phoneLink.deliver()
        #expect(await waitFor { store.listDocuments().filter(\.isComplete).count == 2 })

        // iPhone -> watch
        try await phone.delete(documentId: a.manifest.id)
        phoneLink.deliver()
        #expect(await waitFor { store.document(id: a.manifest.id) == nil })

        // watch -> iPhone
        await receiver.delete(docId: b.manifest.id)
        watchLink.deliver()
        #expect(await waitFor { phoneEvents.all.contains(.deletedOnWatch(docId: b.manifest.id)) })
        #expect(store.listDocuments().isEmpty)
    }

    @Test func missingFileTriggersResendRequest() async throws {
        let root = TestFiles.makeTempDir()
        let (phoneLink, watchLink) = InMemoryLink.pair(root: root)
        let phone = PhoneTransport(link: phoneLink)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let receiver = WatchReceiver(link: watchLink, store: store)
        let phoneEvents = EventLog<TransportEvent>()
        let phoneTask = Task { for await e in phone.events { phoneEvents.append(e) } }
        defer { phoneTask.cancel() }

        let package = try TestFiles.makePackage(pages: 3, in: root)
        try await phone.send(package)
        // Corrupt one queued page before delivery.
        let items = phoneLink.drain()
        let victim = package.manifest.pageFiles[0].name
        for item in items {
            if case .file(let source, let meta) = item, meta.name == victim {
                try Data(count: 64).write(to: source)
            }
            phoneLink.deliverOne(item)
        }
        #expect(await waitFor { watchLink.pendingCount > 0 })
        watchLink.deliver()
        #expect(await waitFor { phoneEvents.all.contains(.resendRequested(docId: package.manifest.id, names: [victim])) })
        try await phone.resend(package, names: [victim])
        phoneLink.deliver()
        #expect(await waitFor { store.isComplete(package.manifest.id) })
        _ = receiver
    }
}

@Suite("Recovery")
struct RecoveryTests {
    @Test func stalledDocumentRequestsMissingFiles() async throws {
        let root = TestFiles.makeTempDir()
        let (phoneLink, watchLink) = InMemoryLink.pair(root: root)
        let phone = PhoneTransport(link: phoneLink)
        let store = DocumentStore(root: root.appendingPathComponent("watch"))
        let receiver = WatchReceiver(link: watchLink, store: store)

        let package = try TestFiles.makePackage(pages: 4, in: root)
        try await phone.send(package)
        // Lose the last page in transit.
        let items = phoneLink.drain()
        for item in items.dropLast() { phoneLink.deliverOne(item) }
        let lost = package.transferOrder.last!.name

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while store.missingFileNames(for: package.manifest.id) != [lost], clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.missingFileNames(for: package.manifest.id) == [lost])
        _ = watchLink.drain()

        #expect(receiver.requestMissingFiles(idleFor: 0) == 1)
        let sent = watchLink.drain()
        guard case .message(let message) = sent.first else {
            Issue.record("No resend message")
            return
        }
        #expect(message == .resend(docId: package.manifest.id, names: [lost]))
        // Recent activity: no request yet.
        #expect(receiver.requestMissingFiles(idleFor: 3600) == 0)
    }
}
