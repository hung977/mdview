import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    @State private var text: String
    @State private var watcher: FileWatcher?
    @State private var showRaw = false

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _text = State(initialValue: document.text)
    }

    var body: some View {
        MarkdownWebView(text: text, baseURL: fileURL?.deletingLastPathComponent(), showRaw: showRaw)
            .toolbar {
                ToolbarItem {
                    Toggle(isOn: $showRaw) {
                        Label("Raw", systemImage: "doc.plaintext")
                    }
                    .toggleStyle(.button)
                    .help(showRaw ? "Show rendered preview" : "Show raw Markdown")
                }
            }
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

    private func reload(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }   // mid-save; next event re-reads
        text = MarkdownDocument.decode(data)
    }
}

// MARK: - WebKit host

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let baseURL: URL?
    let showRaw: Bool

    final class Coordinator {
        var lastText: String?
        var lastShowRaw = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ViewerView {
        ViewerView(baseURL: baseURL)
    }

    func updateNSView(_ viewer: ViewerView, context: Context) {
        if context.coordinator.lastShowRaw != showRaw {
            context.coordinator.lastShowRaw = showRaw
            viewer.webView.setMode(raw: showRaw)
        }
        if context.coordinator.lastText != text {
            context.coordinator.lastText = text
            viewer.webView.render(text)
        }
    }
}

// MARK: - Viewer = native find bar + web view

/// Stacks a native find bar (hidden until ⌘F) above the web view. The find actions from the
/// Edit ▸ Find menu land here.
final class ViewerView: NSView {
    let webView: ViewerWebView
    let findBar = FindBar()

    init(baseURL: URL?) {
        webView = ViewerWebView(baseURL: baseURL)
        super.init(frame: .zero)
        let stack = NSStackView(views: [findBar, webView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            findBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            webView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        findBar.isHidden = true
        findBar.onQueryChange = { [weak self] query in self?.run("findSet(\(FindBar.json(query)))") }
        findBar.onNext = { [weak self] in self?.findNext(nil) }
        findBar.onPrevious = { [weak self] in self?.findPrevious(nil) }
        findBar.onDone = { [weak self] in self?.hideFind() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    static func first(in view: NSView) -> ViewerView? {
        if let found = view as? ViewerView { return found }
        for subview in view.subviews { if let found = first(in: subview) { return found } }
        return nil
    }

    @objc func showFind(_ sender: Any?) {
        findBar.isHidden = false
        window?.makeFirstResponder(findBar.field)
        findBar.field.selectText(nil)
        run("findSet(\(FindBar.json(findBar.field.stringValue)))")
    }

    @objc func findNext(_ sender: Any?) {
        if findBar.isHidden { showFind(sender) } else { run("findNext()") }
    }

    @objc func findPrevious(_ sender: Any?) {
        if findBar.isHidden { showFind(sender) } else { run("findPrevious()") }
    }

    func hideFind() {
        findBar.isHidden = true
        run("findClear()")
        window?.makeFirstResponder(webView)
    }

    /// Runs a find call in the page and shows the status it returns ("3 of 12", "Not found").
    private func run(_ script: String) {
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            self?.findBar.status = result as? String ?? ""
        }
    }
}

/// Small-control find bar modelled on NSTextView's: search field, count, ‹ ›, Done.
final class FindBar: NSView, NSSearchFieldDelegate {
    let field = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let arrows = NSSegmentedControl()
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onDone: (() -> Void)?

    var status: String = "" {
        didSet { countLabel.stringValue = status }
    }

    /// Typing must not reach the document's undo manager (that would mark the file "Edited").
    private let barUndoManager = UndoManager()
    override var undoManager: UndoManager? { barUndoManager }

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = "Find"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = self
        field.target = self
        field.action = #selector(queryChanged)
        field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)   // stretch to fill the bar

        countLabel.controlSize = .small
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .left
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        arrows.segmentCount = 2
        arrows.trackingMode = .momentary
        arrows.controlSize = .small
        arrows.segmentStyle = .rounded
        arrows.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous match"), forSegment: 0)
        arrows.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next match"), forSegment: 1)
        arrows.setWidth(28, forSegment: 0)
        arrows.setWidth(28, forSegment: 1)
        arrows.target = self
        arrows.action = #selector(arrowClicked)
        arrows.setContentHuggingPriority(.required, for: .horizontal)

        doneButton.controlSize = .small
        doneButton.bezelStyle = .rounded
        doneButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        doneButton.target = self
        doneButton.action = #selector(doneClicked)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [field, countLabel, arrows, doneButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: row.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @objc private func queryChanged() { onQueryChange?(field.stringValue) }
    @objc private func arrowClicked() { arrows.selectedSegment == 0 ? onPrevious?() : onNext?() }
    @objc private func doneClicked() { onDone?() }

    // Return / Shift-Return step through matches; Escape closes the bar.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrevious?() } else { onNext?() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDone?()
            return true
        default:
            return false
        }
    }

    static func json(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }
}

/// WKWebView that hosts the bundled viewer page. `render(_:)` hands Markdown to the page's
/// JavaScript, which replaces the document body in place (scroll position survives reloads).
final class ViewerWebView: WKWebView, WKNavigationDelegate {
    private let baseURL: URL?
    private var pageReady = false
    private var pendingMarkdown: String?
    private var pendingScripts: [String] = []
    private var mermaidLoaded = false

    init(baseURL: URL?) {
        self.baseURL = baseURL
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isFraudulentWebsiteWarningEnabled = false
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        allowsBackForwardNavigationGestures = false
        underPageBackgroundColor = .textBackgroundColor
        // A file URL load (not loadHTMLString) is what lets the page show images next to the document.
        loadFileURL(Page.shellURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func render(_ markdown: String) {
        guard pageReady else { pendingMarkdown = markdown; return }
        let needsMermaid = markdown.contains("```mermaid") || markdown.contains("~~~mermaid")
        if needsMermaid && !mermaidLoaded {
            mermaidLoaded = true
            evaluateJavaScript(Page.mermaid) { [weak self] _, _ in self?.callRender(markdown) }
        } else {
            callRender(markdown)
        }
    }

    private func callRender(_ markdown: String) {
        let arguments = [markdown, baseURL?.absoluteString ?? ""]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluateJavaScript("render.apply(null, \(json))") { _, _ in }
    }

    func setMode(raw: Bool) {
        let script = "setMode('\(raw ? "raw" : "preview")')"
        guard pageReady else { pendingScripts.append(script); return }
        evaluateJavaScript(script) { _, _ in }
    }

    /// Nothing in the page is editable, but WebKit still asks for an undo manager; keep it away from
    /// the document's so the window never shows "Edited".
    private let pageUndoManager = UndoManager()
    override var undoManager: UndoManager? { pageUndoManager }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)   // keyboard scrolling and ⌘C work before the first click
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        for script in pendingScripts { evaluateJavaScript(script) { _, _ in } }
        pendingScripts.removeAll()
        if let pending = pendingMarkdown {
            pendingMarkdown = nil
            render(pending)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        // In-page anchors are handled by the page's script; every other click leaves the web view.
        decisionHandler(.cancel)
        if url.isFileURL, ["md", "markdown"].contains(url.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The viewer page assembled once from bundled resources; scripts carry a CSP nonce so HTML
/// embedded in a Markdown file cannot run its own scripts.
enum Page {
    /// The shell written once per process to a temp file so WebKit grants it local file access.
    static let shellURL: URL = {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MarkdownPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("viewer-\(ProcessInfo.processInfo.processIdentifier).html")
        try? shell.write(to: url, atomically: true, encoding: .utf8)
        return url
    }()

    private static let shell: String = {
        let nonce = UUID().uuidString
        let css = [resource("vendor/github-markdown", "css"),
                   resource("vendor/highlight-github.min", "css"),
                   "@media (prefers-color-scheme: dark) {" + resource("vendor/highlight-github-dark.min", "css") + "}",
                   resource("viewer", "css")].joined(separator: "\n")
        let js = [resource("vendor/markdown-it.min", "js"),
                  resource("vendor/highlight.min", "js"),
                  resource("viewer", "js")].joined(separator: "\n;\n")
        return resource("viewer", "html")
            .replacingOccurrences(of: "{{NONCE}}", with: nonce)
            .replacingOccurrences(of: "{{CSS}}", with: css)
            .replacingOccurrences(of: "{{JS}}", with: js)
    }()

    static let mermaid: String = resource("vendor/mermaid.min", "js")

    private static func resource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("missing bundled resource \(name).\(ext)")
            return ""
        }
        return text
    }
}

