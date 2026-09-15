import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    @State private var text: String
    @State private var watcher: FileWatcher?

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _text = State(initialValue: document.text)
    }

    var body: some View {
        MarkdownWebView(text: text, baseURL: fileURL?.deletingLastPathComponent())
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

    final class Coordinator { var lastText: String? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ViewerWebView {
        ViewerWebView(baseURL: baseURL)
    }

    func updateNSView(_ webView: ViewerWebView, context: Context) {
        guard context.coordinator.lastText != text else { return }
        context.coordinator.lastText = text
        webView.render(text)
    }
}

/// WKWebView that hosts the bundled viewer page. `render(_:)` hands Markdown to the page's
/// JavaScript, which replaces the document body in place (scroll position survives reloads).
final class ViewerWebView: WKWebView, WKNavigationDelegate {
    private let baseURL: URL?
    private var pageReady = false
    private var pendingMarkdown: String?
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)   // keyboard scrolling and ⌘C work before the first click
    }

    static func first(in view: NSView) -> ViewerWebView? {
        if let found = view as? ViewerWebView { return found }
        for subview in view.subviews { if let found = first(in: subview) { return found } }
        return nil
    }

    // MARK: Find (targets of the Edit ▸ Find menu)

    @objc func showFind(_ sender: Any?) { evaluateJavaScript("showFind()") { _, _ in } }
    @objc func findNext(_ sender: Any?) { evaluateJavaScript("findNext()") { _, _ in } }
    @objc func findPrevious(_ sender: Any?) { evaluateJavaScript("findPrevious()") { _, _ in } }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
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
