import XCTest
import WebKit
@testable import MarkdownPreview

/// Renders Markdown through the real viewer page and inspects the resulting DOM.
final class ViewerWebViewTests: XCTestCase {
    private var directory: URL!
    private var webView: ViewerWebView!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        webView = ViewerWebView(baseURL: directory)
        webView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    }

    /// Polls `script` until it evaluates to `true` (or times out) — rendering is asynchronous.
    @discardableResult
    private func expectTrue(_ script: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue: Any?
        while Date() < deadline {
            let done = expectation(description: "js")
            webView.evaluateJavaScript("(function(){ try { return !!(\(script)); } catch (e) { return String(e); } })()") { value, _ in
                lastValue = value
                done.fulfill()
            }
            wait(for: [done], timeout: 2)
            if lastValue as? Bool == true { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("\(script) never became true (last: \(String(describing: lastValue)))", file: file, line: line)
        return false
    }

    func testGitHubFlavoredElementsAndHeadingIds() {
        webView.render("""
        ## Mục tiêu

        | a | b |
        |---|---|
        | 1 | 2 |

        - [x] done
        - [ ] todo

        ~~gone~~ **bold**
        """)
        expectTrue("document.querySelector('h2#mục-tiêu')")
        expectTrue("document.querySelector('table td')")
        expectTrue("document.querySelectorAll('input[type=checkbox]').length === 2")
        expectTrue("document.querySelector('input[type=checkbox]:checked')")
        expectTrue("document.querySelector('s, del') && document.querySelector('strong')")
        expectTrue("document.querySelector('li.task-list-item')")
    }

    func testCodeIsHighlightedAndPlainFencesAreNot() {
        webView.render("```swift\nlet x = 1\n```\n\n```\nplain\n```")
        expectTrue("document.querySelector('pre code.language-swift .hljs-keyword')")
        expectTrue("document.querySelectorAll('pre code').length === 2")
    }

    func testLinkifyAndTableOfContentsAnchors() {
        webView.render("- [Section](#section)\n\nSee https://developer.apple.com now.\n\n## Section\n")
        expectTrue("document.querySelector('a[href=\"https://developer.apple.com\"]')")
        expectTrue("document.querySelector('a[href=\"#section\"]') && document.getElementById('section')")
    }

    func testLocalImageLoadsFromDocumentFolder() throws {
        let image = NSImage(size: NSSize(width: 6, height: 4), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("pic.png"))
        webView.render("![pic](pic.png)")
        expectTrue("(function(){ const i = document.querySelector('img'); return i && i.complete && i.naturalWidth === 6; })()")
    }

    func testMermaidDiagramIsRendered() {
        webView.render("```mermaid\nflowchart LR\n  A --> B\n```")
        expectTrue("document.querySelector('pre.mermaid svg')", timeout: 15)
    }

    func testEmbeddedScriptsDoNotRun() {
        webView.render("<script>window.__pwned = 1</script>\n\n<img src=x onerror=\"window.__pwned = 2\">\n\ntext")
        expectTrue("document.querySelector('#content').textContent.includes('text')")
        expectTrue("window.__pwned === undefined")
    }

    func testFindBarCountsAndHighlightsMatchesWithoutTouchingSelection() {
        webView.render("alpha beta gamma beta")
        expectTrue("document.querySelector('#content').textContent.includes('gamma')")
        webView.showFind(nil)
        expectTrue("document.activeElement && document.activeElement.id === 'findinput'")
        expectTrue("(function(){ const i = document.getElementById('findinput'); i.value = 'beta'; i.dispatchEvent(new Event('input')); return true; })()")
        expectTrue("document.getElementById('findcount').textContent === '1 of 2'")
        expectTrue("CSS.highlights.get('find-match').size === 2 && CSS.highlights.get('find-current').size === 1")
        expectTrue("document.activeElement.id === 'findinput' && getSelection().rangeCount <= 1")
        webView.findNext(nil)
        expectTrue("document.getElementById('findcount').textContent === '2 of 2'")
        expectTrue("(function(){ const i = document.getElementById('findinput'); i.value = 'zzz'; i.dispatchEvent(new Event('input')); return true; })()")
        expectTrue("document.getElementById('findcount').textContent === 'Not found'")
    }

    func testRerenderKeepsSinglePageAndUpdatesContent() {
        webView.render("# One")
        expectTrue("document.querySelector('h1#one')")
        webView.render("# Two")
        expectTrue("document.querySelector('h1#two') && !document.querySelector('h1#one')")
    }
}
