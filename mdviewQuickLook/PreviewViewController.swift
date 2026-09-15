import Cocoa
import Quartz

/// Quick Look preview (press Space in Finder) — the same viewer page the app uses.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var webView: ViewerWebView?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        preferredContentSize = view.frame.size
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { handler(error); return }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

        let webView = ViewerWebView(baseURL: url.deletingLastPathComponent())
        webView.frame = view.bounds
        webView.autoresizingMask = [.width, .height]
        view.addSubview(webView)
        self.webView = webView
        webView.render(text) { _ in handler(nil) }   // show the panel once the page has content
    }
}
