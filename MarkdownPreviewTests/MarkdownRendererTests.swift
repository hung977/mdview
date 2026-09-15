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

    func testInlineCodeIsMonospacedWithBackground() {
        let s = render("use `foo` now")
        let i = location(of: "foo", in: s)
        XCTAssertTrue(font(s, at: i).fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertNotNil(s.attribute(.backgroundColor, at: i, effectiveRange: nil))
        XCTAssertNil(s.attribute(.backgroundColor, at: location(of: "use", in: s), effectiveRange: nil))
    }

    func testFencedCodeBlockIsAMonospacedTextBlock() {
        let s = render("```\nlet x = 1\n```\n")
        let i = location(of: "let", in: s)
        XCTAssertTrue(font(s, at: i).fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertEqual(paragraphStyle(s, at: i).textBlocks.count, 1)
        XCTAssertTrue(s.string.hasPrefix("let x = 1\n"))
    }

    func testHighlighterColoursCommentsStringsNumbersKeywords() {
        let s = render("```swift\n// note\nlet s = \"hi\" + 42\n```")
        func color(_ needle: String) -> NSColor? {
            s.attribute(.foregroundColor, at: location(of: needle, in: s), effectiveRange: nil) as? NSColor
        }
        XCTAssertEqual(color("// note"), .secondaryLabelColor)
        XCTAssertEqual(color("let"), .systemPurple)
        XCTAssertEqual(color("\"hi\""), .systemRed)
        XCTAssertEqual(color("42"), .systemBlue)
        XCTAssertEqual(color(" s "), .textColor)
    }

    func testHighlighterSkipsUnknownAndPlainLanguages() {
        XCTAssertEqual(render("```\nlet 1\n```").attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .textColor)
        XCTAssertEqual(render("```text\nlet 1\n```").attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .textColor)
    }

    func testHashCommentsOnlyForHashLanguages() {
        let py = render("```python\n# c\n```")
        XCTAssertEqual(py.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
        let c = render("```c\n#include <x>\n```")
        XCTAssertEqual(c.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .textColor)
    }

    func testInlineBrBecomesLineBreak() {
        XCTAssertEqual(render("a<br>b<br/>c<BR />d").string, "a\u{2028}b\u{2028}c\u{2028}d\n")
        XCTAssertTrue(render("a<span>b").string.contains("<span>"))
    }

    func testTableCellsAreTableBlocksWithBoldHeader() {
        let s = render("| Name | Value |\n|:-----|------:|\n| a | 1 |\n| b | 2 |")
        let header = location(of: "Name", in: s)
        let cell = location(of: "b", in: s)
        let headerBlock = paragraphStyle(s, at: header).textBlocks.first as? NSTextTableBlock
        let cellBlock = paragraphStyle(s, at: cell).textBlocks.first as? NSTextTableBlock
        XCTAssertNotNil(headerBlock); XCTAssertNotNil(cellBlock)
        XCTAssertTrue(headerBlock!.table === cellBlock!.table)
        XCTAssertEqual(headerBlock!.table.numberOfColumns, 2)
        XCTAssertEqual(cellBlock!.startingRow, 2)
        XCTAssertEqual(cellBlock!.startingColumn, 0)
        XCTAssertTrue(font(s, at: header).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertFalse(font(s, at: cell).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(paragraphStyle(s, at: location(of: "2", in: s)).alignment, .right)
        XCTAssertEqual(paragraphStyle(s, at: cell).alignment, .left)
    }

    func testTableShortRowsStillProduceEveryCell() {
        let s = render("| a | b | c |\n|---|---|---|\n| 1 |")
        var cells = Set<String>()
        s.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if let b = (value as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock {
                cells.insert("\(b.startingRow),\(b.startingColumn)")
            }
        }
        XCTAssertEqual(cells.count, 6)
    }

    func testAbsoluteAndRelativeLinks() {
        let base = URL(fileURLWithPath: "/tmp/proj/", isDirectory: true)
        let s = render("[web](https://example.com/x) [doc](docs/a%20b.md#sec) [frag](#top)", baseURL: base)
        XCTAssertEqual(s.attribute(.link, at: location(of: "web", in: s), effectiveRange: nil) as? URL,
                       URL(string: "https://example.com/x"))
        XCTAssertEqual((s.attribute(.link, at: location(of: "doc", in: s), effectiveRange: nil) as? URL)?.path,
                       "/tmp/proj/docs/a b.md")
        XCTAssertNil(s.attribute(.link, at: location(of: "frag", in: s), effectiveRange: nil))
    }

    func testLocalImageBecomesAttachmentAndMissingImageBecomesAltText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: dir.appendingPathComponent("pic.png"))

        let s = render("![alt one](pic.png)\n\n![alt two](missing.png)", baseURL: dir)
        let attachment = s.attribute(.attachment, at: 0, effectiveRange: nil) as? ImageAttachment
        XCTAssertNotNil(attachment?.image)
        XCTAssertTrue(s.string.contains("alt two"))
        XCTAssertFalse(s.string.contains("alt one"))
    }

    func testRemoteImageProducesPendingAttachment() {
        let s = render("![badge](https://example.invalid/badge.svg)")
        XCTAssertTrue(s.attribute(.attachment, at: 0, effectiveRange: nil) is ImageAttachment)
    }

    func testImageAttachmentBoundsFitLineWidth() {
        let image = NSImage(size: NSSize(width: 2000, height: 1000))
        let attachment = ImageAttachment(image: image)
        let bounds = attachment.attachmentBounds(for: nil, proposedLineFragment: CGRect(x: 0, y: 0, width: 500, height: 20),
                                                 glyphPosition: .zero, characterIndex: 0)
        XCTAssertEqual(bounds.width, 500, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 250, accuracy: 0.01)
    }
}
