import Foundation

/// RFC 4180 style CSV parser (quotes, escaped quotes, embedded newlines).
/// Detects `,`, `;` and tab separators (`;` is common in French Excel exports).
public enum CSVParser {
    public static func detectSeparator(in text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let candidates: [Character] = [",", ";", "\t"]
        var best: Character = ","
        var bestCount = 0
        for candidate in candidates {
            var count = 0
            var inQuotes = false
            for ch in firstLine {
                if ch == "\"" { inQuotes.toggle() } else if ch == candidate && !inQuotes { count += 1 }
            }
            if count > bestCount {
                best = candidate
                bestCount = count
            }
        }
        return best
    }

    public static func parse(_ text: String, separator: Character? = nil) -> [[String]] {
        let sep = separator ?? detectSeparator(in: text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let ch = nextChar() {
            if inQuotes {
                if ch == "\"" {
                    if let next = nextChar() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
                continue
            }
            switch ch {
            case "\"" where field.isEmpty:
                inQuotes = true
            case sep:
                row.append(field)
                field = ""
            case "\r\n", "\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
