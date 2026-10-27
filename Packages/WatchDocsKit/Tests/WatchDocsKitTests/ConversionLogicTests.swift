import Foundation
import Testing
@testable import WatchDocsKit

@Suite("Text, CSV and Word logic")
struct ConversionLogicTests {
    @Test func decodesUTF8() {
        let result = TextDecoding.decode(Data("Café crème à Montréal".utf8))
        #expect(result.text == "Café crème à Montréal")
        #expect(result.encoding == .utf8)
    }

    @Test func decodesUTF8WithBOM() {
        let result = TextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("été".utf8))
        #expect(result.text == "été")
    }

    @Test func decodesLatin1() {
        // "Café été" in ISO-8859-1
        let bytes: [UInt8] = [0x43, 0x61, 0x66, 0xE9, 0x20, 0xE9, 0x74, 0xE9]
        let result = TextDecoding.decode(Data(bytes))
        #expect(result.text == "Café été")
        #expect(result.encoding == .isoLatin1)
    }

    @Test func decodesUTF16LE() {
        var data = Data([0xFF, 0xFE])
        data.append("Hé".data(using: .utf16LittleEndian)!)
        #expect(TextDecoding.decode(data).text == "Hé")
    }

    @Test func normalizesNewlines() {
        #expect(TextDecoding.normalizeNewlines("a\r\nb\rc\n") == "a\nb\nc\n")
    }

    @Test func parsesCSVWithQuotes() {
        let csv = "name,note\n\"Dupont, Jean\",\"il a dit \"\"bonjour\"\"\"\nMarie,\"ligne 1\nligne 2\"\n"
        let rows = CSVParser.parse(csv)
        #expect(rows.count == 3)
        #expect(rows[1] == ["Dupont, Jean", "il a dit \"bonjour\""])
        #expect(rows[2] == ["Marie", "ligne 1\nligne 2"])
    }

    @Test func detectsSemicolonSeparator() {
        let csv = "Jour;Heure;Cours\nLundi;9h;INF1120\r\nMardi;13h;INF2120"
        #expect(CSVParser.detectSeparator(in: csv) == ";")
        let rows = CSVParser.parse(csv)
        #expect(rows == [["Jour", "Heure", "Cours"], ["Lundi", "9h", "INF1120"], ["Mardi", "13h", "INF2120"]])
    }

    @Test func extractsWordText() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:r><w:t>Titre</w:t></w:r></w:p>
        <w:p><w:r><w:t xml:space="preserve">Bonjour </w:t></w:r><w:r><w:t>le monde</w:t></w:r></w:p>
        <w:p><w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>c1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>c2</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        </w:body></w:document>
        """
        let text = WordXMLTextExtractor.extract(from: Data(xml.utf8))
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains("Titre"))
        #expect(lines.contains("Bonjour le monde"))
        #expect(lines.contains("A\tB"))
        #expect(lines.contains { $0.hasPrefix("c1") && $0.contains("c2") })
    }
}
