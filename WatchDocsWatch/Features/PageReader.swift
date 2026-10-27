import ImageIO
import Observation
import SwiftUI
import WatchKit
import WatchDocsKit

/// WCH-03 / WCH-04 / WCH-10 / WCH-11.
/// One page at a time, horizontal swipe between pages, Digital Crown zoom (1x to 4x),
/// drag to move when zoomed, double tap to return to 1x. At most 3 decoded pages in memory.
struct PageReader: View {
    let document: StoredDocument
    private let pages: [PackageFile]

    @State private var index: Int
    @State private var zoom: Double = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var cache = PageImageCache()
    @State private var ticketMode = false
    @State private var showJump = false
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    init(document: StoredDocument) {
        self.document = document
        pages = document.manifest.pageFiles
        let saved = ReadingPositions.page(for: document.id)
        _index = State(initialValue: min(max(0, saved), max(0, document.manifest.pageFiles.count - 1)))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                (ticketMode ? Color.white : Color.black).ignoresSafeArea()
                if let image = cache.image(at: index) {
                    let fitted = fittedSize(image.size, in: geometry.size)
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                        .scaleEffect(zoom)
                        .offset(offset)
                        .accessibilityLabel(Text("Page \(index + 1) of \(pages.count)"))
                } else if cache.failed(at: index) {
                    Label("Page unavailable", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                } else {
                    ProgressView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(viewSize: geometry.size))
            .onTapGesture(count: 2) { resetZoom() }
            .focusable()
            .digitalCrownRotation($zoom, from: 1, through: 4, by: 0.05, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: zoom) { _, newZoom in
                if newZoom <= 1.01 { withAnimation(.easeOut(duration: 0.15)) { offset = .zero } }
                offset = clamp(offset, viewSize: geometry.size)
                dragStart = offset
            }
            .overlay(alignment: .top) {
                if pages.count > 1 && !isLuminanceReduced {
                    Button {
                        showJump = true
                    } label: {
                        Text("\(index + 1) / \(pages.count)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Page \(index + 1) of \(pages.count). Go to page"))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    ticketMode.toggle()
                    if ticketMode { resetZoom() }
                } label: {
                    Image(systemName: ticketMode ? "qrcode.viewfinder" : "qrcode")
                }
                .accessibilityLabel(ticketMode ? Text("Exit ticket mode") : Text("Ticket mode"))
            }
        }
        .task(id: index) {
            ReadingPositions.setPage(index, for: document.id)
            await cache.load(around: index, pages: pages, directory: document.directory)
        }
        .sheet(isPresented: $showJump) {
            PageJumpView(current: index, count: pages.count) { target in
                goTo(target)
                showJump = false
            }
        }
    }

    // MARK: Gestures

    private func dragGesture(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard zoom > 1.01 else { return }
                offset = clamp(CGSize(width: dragStart.width + value.translation.width,
                                      height: dragStart.height + value.translation.height), viewSize: viewSize)
            }
            .onEnded { value in
                if zoom > 1.01 {
                    dragStart = offset
                    return
                }
                let dx = value.translation.width
                guard abs(dx) > 30, abs(dx) > abs(value.translation.height) else { return }
                goTo(dx < 0 ? index + 1 : index - 1)
            }
    }

    private func goTo(_ target: Int) {
        let clamped = min(max(0, target), pages.count - 1)
        guard clamped != index else { return }
        index = clamped
        resetZoom()
        WKInterfaceDevice.current().play(.click)
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = 1
            offset = .zero
        }
        dragStart = .zero
    }

    // MARK: Geometry

    private func fittedSize(_ size: CGSize, in container: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return container }
        let scale = min(container.width / size.width, container.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Keeps the zoomed page on screen.
    private func clamp(_ proposed: CGSize, viewSize: CGSize) -> CGSize {
        guard let image = cache.image(at: index) else { return .zero }
        let fitted = fittedSize(image.size, in: viewSize)
        let maxX = max(0, (fitted.width * zoom - viewSize.width) / 2)
        let maxY = max(0, (fitted.height * zoom - viewSize.height) / 2)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }
}

/// Crown-driven page picker, fast even with thousands of pages.
private struct PageJumpView: View {
    let current: Int
    let count: Int
    let onSelect: (Int) -> Void
    @State private var value: Double = 1

    var body: some View {
        VStack(spacing: 8) {
            Text("Go to page")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))")
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .focusable()
                .digitalCrownRotation($value, from: 1, through: Double(max(count, 1)), by: 1, sensitivity: count > 200 ? .high : .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            Text("of \(count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open") { onSelect(Int(value.rounded()) - 1) }
                .buttonStyle(.borderedProminent)
        }
        .onAppear { value = Double(current + 1) }
    }
}

/// Decodes page images on demand and keeps only the current, previous and next pages.
@MainActor
@Observable
final class PageImageCache {
    private var images: [Int: UIImage] = [:]
    private var failures: Set<Int> = []
    /// Upper bound for decoded pages (memory, PRD section 7).
    private let maxPixelSize = 1600

    func image(at index: Int) -> UIImage? { images[index] }
    func failed(at index: Int) -> Bool { failures.contains(index) }

    func load(around index: Int, pages: [PackageFile], directory: URL) async {
        let wanted = [index, index + 1, index - 1].filter { $0 >= 0 && $0 < pages.count }
        // Evict everything outside the window first.
        for key in images.keys where !wanted.contains(key) { images[key] = nil }
        for i in wanted where images[i] == nil && !failures.contains(i) {
            let url = directory.appendingPathComponent(pages[i].name)
            let maxPixels = maxPixelSize
            let decoded = await Task.detached(priority: i == index ? .userInitiated : .utility) {
                Self.decode(url: url, maxPixelSize: maxPixels)
            }.value
            guard !Task.isCancelled else { return }
            if let decoded {
                images[i] = UIImage(cgImage: decoded)
            } else {
                failures.insert(i)
            }
        }
    }

    nonisolated static func decode(url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
