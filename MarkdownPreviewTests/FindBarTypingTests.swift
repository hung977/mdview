import XCTest
import WebKit
import SwiftUI
@testable import MarkdownPreview

/// The find bar must accept keyboard input when the web view sits in a real key window.
final class FindBarTypingTests: XCTestCase {
    func testTypingReachesFindInput() { run(hosting: false) }
    func testTypingReachesFindInputInsideSwiftUIHostingView() { run(hosting: true) }

    private func run(hosting: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let webView: ViewerWebView
        if hosting {
            window.contentView = NSHostingView(rootView: MarkdownWebView(text: "hello world", baseURL: nil))
            window.makeKeyAndOrderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            webView = ViewerWebView.first(in: window.contentView!)!
        } else {
            webView = ViewerWebView(baseURL: nil)
            window.contentView = webView
            window.makeKeyAndOrderFront(nil)
            webView.render("hello world")
        }
        window.makeFirstResponder(webView)

        func js(_ script: String) -> Any? {
            var result: Any?
            let done = expectation(description: "js")
            webView.evaluateJavaScript(script) { value, error in result = value ?? error?.localizedDescription; done.fulfill() }
            wait(for: [done], timeout: 5)
            return result
        }
        var tries = 0
        while (js("document.querySelector('#content').textContent") as? String)?.contains("hello") != true, tries < 100 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)); tries += 1
        }
        webView.showFind(nil)
        tries = 0
        while js("document.activeElement && document.activeElement.id") as? String != "findinput", tries < 100 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)); tries += 1
        }
        XCTAssertEqual(js("document.activeElement.id") as? String, "findinput")
        XCTAssertEqual(window.firstResponder as? NSView, webView)

        for (char, code) in [("w", UInt16(13)), ("o", UInt16(31))] {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: char,
                                             charactersIgnoringModifiers: char, isARepeat: false, keyCode: code)!
                window.sendEvent(event)
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }
        tries = 0
        while js("document.getElementById('findinput').value") as? String != "wo", tries < 40 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)); tries += 1
        }
        XCTAssertEqual(js("document.getElementById('findinput').value") as? String, "wo")
        window.orderOut(nil)
    }
}
