import Foundation

/// Decodes text files whose encoding is unknown (M5: UTF-8 and ISO-8859-1).
public enum TextDecoding {
    public struct Result: Sendable, Equatable {
        public let text: String
        public let encoding: String.Encoding
    }

    /// Order of attempts:
    /// 1. BOM (UTF-8, UTF-16 LE/BE, UTF-32 LE/BE)
    /// 2. strict UTF-8
    /// 3. Windows-1252 if it contains bytes 0x80-0x9F that map to printable characters
    /// 4. ISO-8859-1 (never fails)
    public static func decode(_ data: Data) -> Result {
        if data.isEmpty { return Result(text: "", encoding: .utf8) }
        let bytes = [UInt8](data.prefix(4))

        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF,
           let s = String(data: data.dropFirst(3), encoding: .utf8) {
            return Result(text: s, encoding: .utf8)
        }
        if bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0, bytes[3] == 0,
           let s = String(data: data.dropFirst(4), encoding: .utf32LittleEndian) {
            return Result(text: s, encoding: .utf32LittleEndian)
        }
        if bytes.count >= 4, bytes[0] == 0, bytes[1] == 0, bytes[2] == 0xFE, bytes[3] == 0xFF,
           let s = String(data: data.dropFirst(4), encoding: .utf32BigEndian) {
            return Result(text: s, encoding: .utf32BigEndian)
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE,
           let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return Result(text: s, encoding: .utf16LittleEndian)
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF,
           let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return Result(text: s, encoding: .utf16BigEndian)
        }
        if let s = String(data: data, encoding: .utf8) {
            return Result(text: s, encoding: .utf8)
        }
        let hasC1 = data.contains { $0 >= 0x80 && $0 <= 0x9F }
        if hasC1, let s = String(data: data, encoding: .windowsCP1252) {
            return Result(text: s, encoding: .windowsCP1252)
        }
        let latin1 = String(decoding: data.map { UInt16($0) }, as: UTF16.self)
        return Result(text: latin1, encoding: .isoLatin1)
    }

    /// Normalizes line endings to `\n`.
    public static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
