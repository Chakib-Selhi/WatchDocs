import Foundation
import Testing
@testable import WatchDocsKit

@Suite("Models and packaging")
struct ModelTests {
    @Test func sha256KnownVectors() {
        #expect(FileHasher.sha256(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(FileHasher.sha256(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let long = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        #expect(FileHasher.sha256(of: long) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    @Test func sha256StreamingMatchesInMemory() throws {
        let dir = TestFiles.makeTempDir()
        var data = Data(count: 1_000_003)
        data.withUnsafeMutableBytes { raw in for i in 0..<raw.count { raw[i] = UInt8(i % 251) } }
        let url = dir.appendingPathComponent("big.bin")
        try data.write(to: url)
        #expect(try FileHasher.sha256(of: url) == FileHasher.sha256(of: data))
    }

    @Test func manifestRoundTrip() throws {
        let manifest = DocumentManifest(
            title: "Billet",
            sourceType: .pdf,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            modes: [.pages, .text],
            pageCount: 2,
            files: [
                PackageFile(name: "page_00002.heic", kind: .page, bytes: 10, sha256: "b"),
                PackageFile(name: "page_00001.heic", kind: .page, bytes: 20, sha256: "a"),
                PackageFile(name: "text.txt", kind: .text, bytes: 5, sha256: "c"),
            ]
        )
        let decoded = try DocumentManifest.decode(from: manifest.encoded())
        #expect(decoded == manifest)
        #expect(decoded.totalBytes == 35)
        #expect(decoded.pageFiles.map(\.name) == ["page_00001.heic", "page_00002.heic"])
        #expect(decoded.schemaVersion == 1)
    }

    @Test func pageNamingSortsBeyondFiveDigits() {
        #expect(PackageNaming.pageFileName(index: 0, fileExtension: "heic") == "page_00001.heic")
        #expect(PackageNaming.pageIndex("page_00012.heic") == 11)
        #expect(PackageNaming.pageIndex("page_123456.heic") == 123_455)
        #expect(PackageNaming.pageIndex("page_99999.heic") < PackageNaming.pageIndex("page_100000.heic"))
    }

    @Test func unsafeNamesAreRejected() {
        #expect(!PackageNaming.isSafe("../x"))
        #expect(!PackageNaming.isSafe("a/b"))
        #expect(!PackageNaming.isSafe(".complete"))
        #expect(PackageNaming.isSafe("page_00001.heic"))
    }

    @Test func packageBuilderHashesEveryFile() throws {
        let root = TestFiles.makeTempDir()
        let package = try TestFiles.makePackage(pages: 3, in: root)
        #expect(package.manifest.pageCount == 3)
        #expect(package.manifest.files.count == 5)
        #expect(package.allFilesPresent())
        #expect(package.transferOrder.first?.kind == .thumbnail)
        #expect(package.transferOrder.last?.name == "page_00003.heic")
        let reloaded = try DocumentPackage.load(from: package.directory)
        #expect(reloaded.manifest == package.manifest)
        for file in package.manifest.files {
            #expect(try FileHasher.sha256(of: package.url(for: file)) == file.sha256)
        }
    }

    @Test func tableSheetIsRectangular() throws {
        let sheet = TableSheet(name: "Feuil1", rows: [["a", "b", "c"], ["d"]])
        #expect(sheet.columns == 3)
        #expect(sheet.rows[1] == ["d", "", ""])
        #expect(try TableSheet.decode(from: sheet.encoded()) == sheet)
    }

    @Test func transportMessagesRoundTrip() throws {
        let id = UUID()
        for message in [TransportMessage.ack(docId: id), .delete(docId: id), .rename(docId: id, title: "É"), .resend(docId: id, names: ["a"])] {
            let info: [String: Any] = try message.userInfo()
            #expect(TransportMessage.from(userInfo: info) == message)
        }
        let meta = FileMetadata(docId: id, name: "page_00001.heic", kind: .page, index: 3)
        let dict: [String: Any] = try meta.dictionary()
        #expect(FileMetadata.from(dict) == meta)
    }

    @Test func storageCheck() throws {
        let context = WatchContext(documentCount: 1, usedBytes: 100_000_000, freeBytes: 1_000_000_000)
        try PhoneTransport.checkStorage(packageBytes: 50_000_000, context: context, userLimit: nil)
        #expect(throws: TransportError.self) {
            try PhoneTransport.checkStorage(packageBytes: 990_000_000, context: context, userLimit: nil)
        }
        #expect(throws: TransportError.self) {
            try PhoneTransport.checkStorage(packageBytes: 50_000_000, context: context, userLimit: 120_000_000)
        }
        // Unknown watch state: accepted.
        try PhoneTransport.checkStorage(packageBytes: 5_000_000_000, context: nil, userLimit: 1)
    }

    @Test func sourceClassification() {
        #expect(SourceClassifier.sourceType(forExtension: "PDF") == .pdf)
        #expect(SourceClassifier.sourceType(forExtension: "heic") == .image)
        #expect(SourceClassifier.sourceType(forExtension: "docx") == .word)
        #expect(SourceClassifier.sourceType(forExtension: "csv") == .excel)
        #expect(SourceClassifier.sourceType(forExtension: "md") == .text)
        #expect(SourceClassifier.sourceType(forExtension: "zip") == nil)
        #expect(SourceClassifier.title(forFileName: "Billet Air Canada.pdf") == "Billet Air Canada")
    }
}
