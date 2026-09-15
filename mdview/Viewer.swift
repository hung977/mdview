import WebKit

/// One entry of the document outline (sidebar). `id` is the heading's anchor in the page.
struct Heading: Codable, Identifiable, Hashable {
    let id: String
    let level: Int
    let text: String
}

/// Counts shown in the Info inspector.
struct DocumentStats: Codable, Equatable {
    var words = 0, characters = 0, lines = 0, links = 0, images = 0, tables = 0, codeBlocks = 0, diagrams = 0
}

/// What the page reports after each render.
struct RenderResult: Codable {
    var outline: [Heading] = []
    var stats = DocumentStats()
}

/// WKWebView that hosts the bundled viewer page. `render(_:)` hands Markdown to the page's
/// JavaScript, which replaces the document body in place (scroll position survives reloads).
final class ViewerWebView: WKWebView, WKNavigationDelegate {
    private let baseURL: URL?
    private var pageReady = false
    private var pendingMarkdown: (text: String, completion: ((RenderResult) -> Void)?)?
    private var pendingWork: [() -> Void] = []
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

    /// Renders `markdown`; `completion` receives the outline and statistics once the page has been updated.
    func render(_ markdown: String, completion: ((RenderResult) -> Void)? = nil) {
        guard pageReady else { pendingMarkdown = (markdown, completion); return }
        let needsMermaid = markdown.contains("```mermaid") || markdown.contains("~~~mermaid")
        if needsMermaid && !mermaidLoaded {
            mermaidLoaded = true
            evaluateJavaScript(Page.mermaid) { [weak self] _, _ in self?.callRender(markdown, completion: completion) }
        } else {
            callRender(markdown, completion: completion)
        }
    }

    private func callRender(_ markdown: String, completion: ((RenderResult) -> Void)?) {
        let arguments = [markdown, baseURL?.absoluteString ?? ""]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { completion?(RenderResult()); return }
        evaluateJavaScript("render.apply(null, \(json))") { result, _ in
            let decoded = (result as? String).flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode(RenderResult.self, from: $0) } ?? RenderResult()
            completion?(decoded)
        }
    }

    /// Page zoom (⌘+ / ⌘− / ⌘0). CSS pixels scale with it, so the chrome inset is re-sent.
    var zoom: CGFloat {
        get { pageZoom }
        set {
            pageZoom = min(max(newValue, 0.5), 3)
            sendTopInset()
        }
    }

    private var topInset: CGFloat = 0
    func setTopInset(_ points: CGFloat) {
        topInset = points
        sendTopInset()
    }
    private func sendTopInset() {
        evaluate("setTopInset(\(topInset / pageZoom))") { _ in }
    }

    func scrollToHeading(_ id: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: id, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluate("scrollToHeading(\(json))") { _ in }
    }

    func setMode(raw: Bool) {
        evaluate("setMode('\(raw ? "raw" : "preview")')") { _ in }
    }

    /// Runs `script` once the page is ready (calls made during loading are queued in order).
    func evaluate(_ script: String, completion: @escaping (Any?) -> Void) {
        guard pageReady else {
            pendingWork.append { [weak self] in self?.evaluate(script, completion: completion) }
            return
        }
        evaluateJavaScript(script) { result, _ in completion(result) }
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
        if let pending = pendingMarkdown {          // content first, then queued calls (find, mode)
            pendingMarkdown = nil
            render(pending.text, completion: pending.completion)
        }
        let work = pendingWork
        pendingWork.removeAll()
        work.forEach { $0() }
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mdview", isDirectory: true)
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
        guard let url = Bundle(for: ViewerWebView.self).url(forResource: name, withExtension: ext, subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("missing bundled resource \(name).\(ext)")
            return ""
        }
        return text
    }
}


