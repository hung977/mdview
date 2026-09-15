import XCTest
import AppKit
@testable import MarkdownPreview

final class MarkdownRendererTests: XCTestCase {
    private func render(_ md: String, baseURL: URL? = nil) -> NSAttributedString {
        MarkdownRenderer.render(md, baseURL: baseURL)
    }
    private func font(_ s: NSAttributedString, at i: Int = 0) -> NSFont {
        s.attribute(.font, at: i, effectiveRange: nil) as! NSFont
    }
    private func paragraphStyle(_ s: NSAttributedString, at i: Int = 0) -> NSParagraphStyle {
        s.attribute(.paragraphStyle, at: i, effectiveRange: nil) as! NSParagraphStyle
    }
    private func location(of needle: String, in s: NSAttributedString) -> Int {
        let r = (s.string as NSString).range(of: needle)
        XCTAssertNotEqual(r.location, NSNotFound, "\(needle) not found in \(s.string)")
        return r.location
    }

    func testHeadingLevelsUseBoldDescendingSizes() {
        let h1 = render("# One"), h2 = render("## Two")
        XCTAssertTrue(font(h1).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertGreaterThan(font(h1).pointSize, font(h2).pointSize)
        XCTAssertGreaterThan(font(h2).pointSize, Style.body.pointSize)
    }

    func testParagraphUsesBodyFontAndEndsWithNewline() {
        let s = render("plain text")
        XCTAssertEqual(font(s).pointSize, Style.body.pointSize)
        XCTAssertTrue(s.string.hasSuffix("\n"))
        XCTAssertEqual(paragraphStyle(s).paragraphSpacing, Style.spacing)
    }

    func testStrongEmphasisAndStrikethrough() {
        let s = render("**b** *i* ~~s~~")
        XCTAssertTrue(font(s, at: location(of: "b", in: s)).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(font(s, at: location(of: "i", in: s)).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertNotNil(s.attribute(.strikethroughStyle, at: location(of: "s", in: s), effectiveRange: nil))
        XCTAssertFalse(font(s, at: location(of: " ", in: s)).fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testHardLineBreakStaysInsideParagraph() {
        let s = render("a  \nb")
        XCTAssertEqual(s.string, "a\u{2028}b\n")
    }
}
