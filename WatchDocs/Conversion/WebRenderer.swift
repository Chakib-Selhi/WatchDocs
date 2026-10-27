import Foundation
import UIKit
import WebKit

/// Off-screen WKWebView used to lay out Word, Excel and HTML content and
/// print it to a paginated PDF (PRD section 3, M6).
@MainActor
final class WebRenderer: NSObject, WKNavigationDelegate {
    /// A5-like paper: narrow pages give bigger text on the watch.
    static let paperRect = CGRect(x: 0, y: 0, width: 420, height: 595)
    static let margin: CGFloat = 18

    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: Self.paperRect.width, height: Self.paperRect.height), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        // Some content only lays out inside a window.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first })
            .first {
            window.insertSubview(webView, at: 0)
        }
    }

    deinit {
        let view = webView
        Task { @MainActor in view.removeFromSuperview() }
    }

    // MARK: Loading

    func load(fileURL: URL) async throws {
        try await withLoad {
            self.webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }
    }

    func load(html: String, baseURL: URL? = nil) async throws {
        try await withLoad {
            self.webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private func withLoad(_ start: @escaping () -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.loadContinuation = continuation
                    start()
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(45))
                throw ConversionError.renderFailed
            }
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                self.finishLoad(.failure(error))
                throw error
            }
        }
        // Let WebKit finish layout (QuickLook based Office rendering is asynchronous).
        try await Task.sleep(for: .milliseconds(600))
    }

    private func finishLoad(_ result: Result<Void, Error>) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        continuation.resume(with: result)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishLoad(.success(())) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishLoad(.failure(ConversionError.renderFailed)) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishLoad(.failure(ConversionError.renderFailed)) }
    }

    // MARK: Output

    /// Visible text of the loaded page (fallback text extraction for .doc, .xls...).
    func innerText() async -> String? {
        let result = try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''")
        return result as? String
    }

    /// Paginates the loaded content into a PDF. Falls back to `createPDF`
    /// (one tall page) when the print formatter produces nothing.
    func makePDF() async throws -> Data {
        let data = Self.paginate(formatter: webView.viewPrintFormatter())
        if let data { return data }
        let configuration = WKPDFConfiguration()
        return try await webView.pdf(configuration: configuration)
    }

    /// Generic paginator, also used for attributed text (RTF).
    static func paginate(formatter: UIPrintFormatter) -> Data? {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let paper = paperRect
        let printable = paper.insetBy(dx: margin, dy: margin)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let pages = renderer.numberOfPages
        guard pages > 0 else { return nil }
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        for index in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data.length > 0 ? data as Data : nil
    }

    static func paginate(attributedText: NSAttributedString) -> Data? {
        paginate(formatter: UISimpleTextPrintFormatter(attributedText: attributedText))
    }
}
