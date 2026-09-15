import XCTest
@testable import MarkdownPreview

final class MarkdownRendererTests: XCTestCase {
    func testRendererReturnsSomething() {
        XCTAssertGreaterThan(MarkdownRenderer.render("hello", baseURL: nil).length, 0)
    }
}
