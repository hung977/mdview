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

    func testNestedListsIndentPerLevel() {
        let s = render("- a\n  - b\n1. c")
        let a = paragraphStyle(s, at: location(of: "a", in: s))
        let b = paragraphStyle(s, at: location(of: "b", in: s))
        XCTAssertEqual(a.headIndent, Style.indent)
        XCTAssertEqual(a.firstLineHeadIndent, 0)
        XCTAssertEqual(b.headIndent, Style.indent * 2)
        XCTAssertTrue(s.string.contains("•\ta"))
        XCTAssertTrue(s.string.contains("1.\tc"))
    }

    func testOrderedListHonoursStartIndex() {
        let s = render("3. x\n4. y")
        XCTAssertTrue(s.string.contains("3.\tx"))
        XCTAssertTrue(s.string.contains("4.\ty"))
    }

    func testTopLevelListEndsWithBlockSpacing() {
        let s = render("- a\n- b\n\nafter")
        let b = paragraphStyle(s, at: location(of: "b", in: s))
        XCTAssertEqual(b.paragraphSpacing, Style.spacing)
        let a = paragraphStyle(s, at: location(of: "a", in: s))
        XCTAssertEqual(a.paragraphSpacing, Style.listSpacing)
    }

    func testTaskItemsUseAttachmentMarkers() {
        let s = render("- [x] done\n- [ ] todo")
        let attachment = s.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        XCTAssertNotNil(attachment?.image)
        XCTAssertEqual(s.string.filter { $0 == "\u{FFFC}" }.count, 2)
    }

    func testBlockquoteUsesTextBlockAndSecondaryColor() {
        let s = render("> quoted")
        let i = location(of: "quoted", in: s)
        XCTAssertEqual(paragraphStyle(s, at: i).textBlocks.count, 1)
        XCTAssertEqual(s.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
    }

    func testThematicBreakIsASeparatorColouredBlock() {
        let s = render("a\n\n---\n\nb")
        var found = false
        s.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if let style = value as? NSParagraphStyle, style.textBlocks.first?.backgroundColor == .separatorColor { found = true }
        }
        XCTAssertTrue(found)
    }
}
