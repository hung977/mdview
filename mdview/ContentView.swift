import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    @State private var text: String
    @State private var watcher: FileWatcher?
    @State private var showRaw = false
    @State private var showInfo = false
    @State private var outline: [Heading] = []
    @State private var selectedHeading: Heading.ID?
    @State private var scrollRequest: ScrollRequest?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var findStatus = ""
    @State private var zoom: CGFloat = 1

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _text = State(initialValue: document.text)
    }

    var body: some View {
        NavigationSplitView {
            List(outline, selection: $selectedHeading) { heading in
                Text(heading.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(heading.level <= 1 ? .body.weight(.semibold) : .body)
                    .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
            .overlay {
                if outline.isEmpty {
                    Text("No Headings").foregroundStyle(.secondary)
                }
            }
        } detail: {
            MarkdownWebView(text: text, baseURL: fileURL?.deletingLastPathComponent(), showRaw: showRaw,
                            scrollRequest: scrollRequest, query: query,
                            onOutline: { outline = $0 }, onFindStatus: { findStatus = $0 },
                            onZoomChange: { zoom = $0 })
                .ignoresSafeArea(.container, edges: .top)   // page scrolls under the glass toolbar
                .toolbar { toolbarItems }
                .searchable(text: $query, placement: .toolbar, prompt: "Search")
                .searchFocused($searchFocused)
                .onSubmit(of: .search) { ViewerView.inKeyWindow()?.findNext(nil) }
        }
        .onChange(of: selectedHeading) { _, id in
            guard let id else { return }
            scrollRequest = ScrollRequest(id: id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mdviewFocusSearch)) { _ in searchFocused = true }
        .onAppear {
            guard watcher == nil, let fileURL else { return }
            watcher = FileWatcher(url: fileURL) { reload(from: fileURL) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, ["md", "markdown"].contains(url.pathExtension.lowercased()) else { return }
                    DispatchQueue.main.async {
                        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                    }
                }
            }
            return true
        }
    }

    // Preview.app-style groups: zoom | raw | find results | info · share | search field.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup {
            Button { ViewerView.inKeyWindow()?.zoomOut(nil) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
            Button { ViewerView.inKeyWindow()?.actualSize(nil) } label: {
                Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().frame(minWidth: 40)
            }
            .help("Actual Size")
            Button { ViewerView.inKeyWindow()?.zoomIn(nil) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
        }
        if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
        ToolbarItem {
            Toggle(isOn: $showRaw) { Label("Raw", systemImage: "doc.plaintext") }
                .toggleStyle(.button)
                .help(showRaw ? "Show rendered preview" : "Show raw Markdown")
        }
        if !query.isEmpty {
            if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
            ToolbarItemGroup {
                Text(findStatus).foregroundStyle(.secondary).monospacedDigit().padding(.leading, 8)
                Button { ViewerView.inKeyWindow()?.findPrevious(nil) } label: { Label("Previous Match", systemImage: "chevron.up") }
                Button { ViewerView.inKeyWindow()?.findNext(nil) } label: { Label("Next Match", systemImage: "chevron.down") }
            }
        }
        if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
        ToolbarItemGroup {
            Button { showInfo.toggle() } label: { Label("Info", systemImage: "info") }
                .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                    FileInfoView(fileURL: fileURL, text: text, headings: outline.count)
                }
            if let fileURL {
                ShareLink(item: fileURL) { Label("Share", systemImage: "square.and.arrow.up") }
            }
        }
    }

    private func reload(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }   // mid-save; next event re-reads
        text = MarkdownDocument.decode(data)
    }
}

extension Notification.Name {
    static let mdviewFocusSearch = Notification.Name("mdview.focusSearch")
}

/// The "i" popover: what Finder's Get Info shows, plus text statistics.
struct FileInfoView: View {
    let fileURL: URL?
    let text: String
    let headings: Int

    var body: some View {
        let attributes = fileURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) } ?? [:]
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            if let fileURL {
                row("Name", fileURL.lastPathComponent)
                row("Where", fileURL.deletingLastPathComponent().path(percentEncoded: false))
            }
            if let size = attributes[.size] as? Int {
                row("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            if let modified = attributes[.modificationDate] as? Date {
                row("Modified", modified.formatted(date: .abbreviated, time: .shortened))
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            row("Words", words.formatted())
            row("Characters", text.count.formatted())
            row("Lines", lines.formatted())
            row("Headings", headings.formatted())
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: 420)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(3)
        }
    }
}

/// A sidebar click; a fresh value each time so re-selecting after scrolling away works too.
struct ScrollRequest: Equatable {
    let id: Heading.ID
    let token = UUID()
}

// MARK: - WebKit host

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let baseURL: URL?
    let showRaw: Bool
    let scrollRequest: ScrollRequest?
    let query: String
    let onOutline: ([Heading]) -> Void
    let onFindStatus: (String) -> Void
    let onZoomChange: (CGFloat) -> Void

    final class Coordinator {
        var lastText: String?
        var lastShowRaw = false
        var lastScrollRequest: ScrollRequest?
        var lastQuery = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ViewerView {
        ViewerView(baseURL: baseURL)
    }

    func updateNSView(_ viewer: ViewerView, context: Context) {
        let coordinator = context.coordinator
        let onFindStatus = onFindStatus, onZoomChange = onZoomChange
        viewer.onFindStatus = { status in DispatchQueue.main.async { onFindStatus(status) } }
        viewer.onZoomChange = { zoom in DispatchQueue.main.async { onZoomChange(zoom) } }
        if coordinator.lastShowRaw != showRaw {
            coordinator.lastShowRaw = showRaw
            viewer.webView.setMode(raw: showRaw)
        }
        if coordinator.lastText != text {
            coordinator.lastText = text
            let onOutline = onOutline
            viewer.webView.render(text) { outline in DispatchQueue.main.async { onOutline(outline) } }
        }
        if coordinator.lastScrollRequest != scrollRequest, let scrollRequest {
            coordinator.lastScrollRequest = scrollRequest
            viewer.webView.scrollToHeading(scrollRequest.id)
        }
        if coordinator.lastQuery != query {
            coordinator.lastQuery = query
            viewer.find(query)
        }
    }
}

// MARK: - Viewer = web view + window-level actions (find, zoom)

/// Hosts the web view under the window's toolbar and is the target of menu/toolbar actions
/// for the key window (`inKeyWindow()`).
final class ViewerView: NSView {
    let webView: ViewerWebView
    var onFindStatus: ((String) -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?
    private var lastInset: CGFloat = -1

    init(baseURL: URL?) {
        webView = ViewerWebView(baseURL: baseURL)
        super.init(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    static func first(in view: NSView) -> ViewerView? {
        if let found = view as? ViewerView { return found }
        for subview in view.subviews { if let found = first(in: subview) { return found } }
        return nil
    }

    static func inKeyWindow() -> ViewerView? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.contentView.flatMap(first(in:))
    }

    /// Tells the page how much window chrome (the toolbar) it scrolls underneath.
    override func layout() {
        super.layout()
        var chrome: CGFloat = 0
        if let window {
            let topInWindow = convert(bounds, to: nil).maxY
            chrome = max(0, topInWindow - window.contentLayoutRect.maxY)
        }
        if chrome != lastInset {
            lastInset = chrome
            webView.setTopInset(chrome)
        }
    }

    // MARK: Find

    func find(_ query: String) { run("findSet(\(json(query)))") }
    @objc func findNext(_ sender: Any?) { run("findNext()") }
    @objc func findPrevious(_ sender: Any?) { run("findPrevious()") }

    private func run(_ script: String) {
        webView.evaluate(script) { [weak self] result in self?.onFindStatus?(result as? String ?? "") }
    }

    private func json(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }

    // MARK: Zoom

    @objc func zoomIn(_ sender: Any?) { setZoom(webView.zoom * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(webView.zoom / 1.1) }
    @objc func actualSize(_ sender: Any?) { setZoom(1) }

    private func setZoom(_ value: CGFloat) {
        webView.zoom = value
        onZoomChange?(webView.zoom)
    }
}
