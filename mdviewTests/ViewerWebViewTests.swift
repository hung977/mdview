import XCTest
import WebKit
@testable import mdview

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

    func testFindApiCountsAndHighlightsMatchesWithoutTouchingSelection() {
        webView.render("alpha beta gamma beta")
        expectTrue("document.querySelector('#content').textContent.includes('gamma')")
        expectTrue("findSet('beta') === '1 of 2'")
        expectTrue("CSS.highlights.get('find-match').size === 2 && CSS.highlights.get('find-current').size === 1")
        expectTrue("getSelection().rangeCount === 0 || getSelection().isCollapsed")
        expectTrue("findNext() === '2 of 2' && findNext() === '1 of 2' && findPrevious() === '2 of 2'")
        expectTrue("findSet('zzz') === 'Not found'")
        expectTrue("findClear() === '' && CSS.highlights.get('find-current').size === 0 && CSS.highlights.get('find-match').size === 0")
        // A new query must fully replace the previous matches.
        expectTrue("findSet('alpha') === '1 of 1' && CSS.highlights.get('find-match').size === 1")
    }

    func testRerenderKeepsSinglePageAndUpdatesContent() {
        webView.render("# One")
        expectTrue("document.querySelector('h1#one')")
        webView.render("# Two")
        expectTrue("document.querySelector('h1#two') && !document.querySelector('h1#one')")
    }

    func testRawModeShowsSourceVerbatimAndPreviewComesBack() {
        webView.render("# Title\n\n**bold** <b>x</b>")
        expectTrue("document.querySelector('h1#title')")
        webView.setMode(raw: true)
        expectTrue("document.querySelector('pre.raw-source code') && document.querySelector('pre.raw-source').textContent === '# Title\\n\\n**bold** <b>x</b>'")
        expectTrue("!document.querySelector('h1') && !document.querySelector('b')")
        webView.setMode(raw: false)
        expectTrue("document.querySelector('h1#title') && !document.querySelector('pre.raw-source')")
    }

    func testRawModeRequestedBeforePageLoadIsHonoured() {
        let early = ViewerWebView(baseURL: nil)
        early.setMode(raw: true)
        early.render("# Early")
        webView = early
        expectTrue("document.querySelector('pre.raw-source') && document.querySelector('pre.raw-source').textContent === '# Early'")
    }

    func testRenderReturnsOutlineMatchingHeadingIdsInBothModes() {
        var outline: [Heading] = []
        var stats = DocumentStats()
        let done = expectation(description: "render")
        webView.render("# Title\n\n## Mục tiêu\n\ntext [a](https://x.y)\n\n## Mục tiêu\n\n### Deep\n\n| a |\n|---|\n| 1 |\n") { outline = $0.outline; stats = $0.stats; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(stats.links, 1); XCTAssertEqual(stats.tables, 1); XCTAssertEqual(stats.lines, 14)
        XCTAssertGreaterThan(stats.words, 5)
        XCTAssertEqual(outline.map(\.id), ["title", "mục-tiêu", "mục-tiêu-1", "deep"])
        XCTAssertEqual(outline.map(\.level), [1, 2, 2, 3])
        expectTrue("document.getElementById('mục-tiêu-1') && document.getElementById('deep')")
        expectTrue("scrollToHeading('deep') === true && scrollToHeading('nope') === false")
        webView.setMode(raw: true)
        expectTrue("document.querySelector('pre.raw-source #mục-tiêu-1') && document.querySelector('#deep').textContent === '### Deep'")
    }

    /// Paint-level check: highlights of a previous query must disappear when the query changes or is cleared.
    func testStaleHighlightsAreRepaintedAway() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFront(nil)
        webView.render(String(repeating: "alpha beta gamma. ", count: 40))
        expectTrue("document.querySelector('#content').textContent.includes('gamma')")
        webView.zoom = 1.21   // the report came from a zoomed window

        func highlightedPixels() -> Int {
            var count = 0
            let done = expectation(description: "snapshot")
            webView.takeSnapshot(with: nil) { image, _ in
                if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                            if let c = rep.colorAt(x: x, y: y), c.redComponent > 0.9, c.greenComponent > 0.75, c.blueComponent < 0.75 { count += 1 }
                        }
                    }
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
            return count
        }

        expectTrue("findSet('beta') === '1 of 40'")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let withBeta = highlightedPixels()
        XCTAssertGreaterThan(withBeta, 50, "matches should be painted")

        expectTrue("findSet('zzz') === 'Not found'")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(highlightedPixels(), 0, "old highlights must be gone after a new query")

        // Same thing for content that was off screen while the query changed.
        webView.render(String(repeating: "alpha beta gamma.\n\n", count: 120))
        expectTrue("document.querySelectorAll('#content p').length === 120")
        expectTrue("findSet('beta') === '1 of 120'")
        expectTrue("(scrollTo(0, 2400), true)")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertGreaterThan(highlightedPixels(), 50, "off-screen matches painted after scrolling to them")
        expectTrue("(scrollTo(0, 0), true)")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        expectTrue("findSet('zzz') === 'Not found'")
        expectTrue("(scrollTo(0, 2400), true)")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(highlightedPixels(), 0, "stale highlights must not survive off screen")

        expectTrue("findSet('gamma') === '1 of 120'")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertGreaterThan(highlightedPixels(), 50)
        expectTrue("findSet('') === ''")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(highlightedPixels(), 0, "clearing the query must clear the paint")
        window.orderOut(nil)
    }
}
