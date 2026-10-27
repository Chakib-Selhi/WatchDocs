import Foundation

/// File naming rules shared by the converter (iPhone) and the reader (watch).
public enum PackageNaming {
    public static let textFileName = "text.txt"

    /// `page_00001.heic`. Five digits keeps lexical order up to 99 999 pages,
    /// and sorting still works beyond that because `pageIndex` parses the number.
    public static func pageFileName(index: Int, fileExtension: String) -> String {
        "page_" + String(format: "%05d", index + 1) + "." + fileExtension
    }

    public static func sheetFileName(index: Int) -> String {
        "sheet_\(index + 1).json"
    }

    public static func thumbnailFileName(fileExtension: String) -> String {
        "thumb." + fileExtension
    }

    /// Zero based page index parsed from a page file name, or `Int.max`.
    public static func pageIndex(_ name: String) -> Int {
        number(in: name, prefix: "page_").map { $0 - 1 } ?? Int.max
    }

    public static func sheetIndex(_ name: String) -> Int {
        number(in: name, prefix: "sheet_").map { $0 - 1 } ?? Int.max
    }

    private static func number(in name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        let rest = name.dropFirst(prefix.count)
        let digits = rest.prefix { $0.isNumber }
        return Int(digits)
    }

    /// Rejects names that could escape the document folder.
    public static func isSafe(_ name: String) -> Bool {
        !name.isEmpty
            && !name.contains("/")
            && !name.contains("\\")
            && name != "."
            && name != ".."
            && !name.hasPrefix(".")
    }
}
