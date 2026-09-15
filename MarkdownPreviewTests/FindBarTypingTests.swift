import XCTest
import SwiftUI
@testable import MarkdownPreview

/// ⌘F opens a native find bar; typing there must reach the search field and never the document's undo manager.
final class FindBarTypingTests: XCTestCase {
    func testTypingReachesFindField() { run(hosting: false) }
    func testTypingReachesFindFieldInsideSwiftUIHostingView() { run(hosting: true) }

    private func run(hosting: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let viewer: ViewerView
        if hosting {
            window.contentView = NSHostingView(rootView: MarkdownWebView(text: "hello world", baseURL: nil, showRaw: false))
            window.makeKeyAndOrderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            viewer = ViewerView.first(in: window.contentView!)!
        } else {
            viewer = ViewerView(baseURL: nil)
            window.contentView = viewer
            window.makeKeyAndOrderFront(nil)
            viewer.webView.render("hello world")
        }
        XCTAssertTrue(viewer.findBar.isHidden)
        viewer.showFind(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(viewer.findBar.isHidden)
        XCTAssertTrue((window.firstResponder as? NSText)?.delegate === viewer.findBar.field, "search field should be editing")

        for (char, code) in [("w", UInt16(13)), ("o", UInt16(31))] {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: char,
                                             charactersIgnoringModifiers: char, isARepeat: false, keyCode: code)!
                window.sendEvent(event)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        XCTAssertEqual(viewer.findBar.field.stringValue, "wo")
        // Nothing may reach the window/document undo manager (that is what marks a document "Edited").
        XCTAssertFalse(window.undoManager?.canUndo ?? false)

        // Status arrives asynchronously from the page.
        var tries = 0
        while viewer.findBar.status != "1 of 1", tries < 100 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); tries += 1 }
        XCTAssertEqual(viewer.findBar.status, "1 of 1")

        viewer.hideFind()
        XCTAssertTrue(viewer.findBar.isHidden)
        XCTAssertTrue(window.firstResponder === viewer.webView)
        window.orderOut(nil)
    }
}
