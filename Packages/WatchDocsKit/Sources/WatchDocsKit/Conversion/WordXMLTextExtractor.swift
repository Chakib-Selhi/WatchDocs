import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Extracts readable text from `word/document.xml` (the main part of a .docx).
/// Paragraphs become lines, `<w:tab/>` becomes a tab, `<w:br/>` a newline.
public final class WordXMLTextExtractor: NSObject, XMLParserDelegate {
    private var output = ""
    private var paragraph = ""
    private var inText = false
    private var tableCellCount = 0

    public static func extract(from data: Data) -> String {
        let extractor = WordXMLTextExtractor()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = extractor
        _ = parser.parse()
        extractor.flushParagraph()
        return extractor.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func flushParagraph() {
        if !paragraph.isEmpty || !output.isEmpty {
            output += paragraph + "\n"
        }
        paragraph = ""
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:t": inText = true
        case "w:tab": paragraph += "\t"
        case "w:br", "w:cr": paragraph += "\n"
        case "w:tc":
            if tableCellCount > 0 { paragraph += "\t" }
            tableCellCount += 1
        case "w:tr": tableCellCount = 0
        default: break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t": inText = false
        case "w:p":
            // Paragraphs inside table cells stay on the row line.
            if tableCellCount == 0 { flushParagraph() } else { paragraph += " " }
        case "w:tr":
            tableCellCount = 0
            flushParagraph()
        default: break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { paragraph += string }
    }
}
