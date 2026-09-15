import AppKit
import Markdown

enum MarkdownRenderer {
    static func render(_ markdown: String, baseURL: URL?) -> NSAttributedString {
        var visitor = Visitor(baseURL: baseURL)
        return visitor.visit(Document(parsing: markdown))
    }
}

// MARK: - Style

enum Style {
    static let maxWidth: CGFloat = 720
    static let body = NSFont.systemFont(ofSize: 15)
    static let spacing: CGFloat = 12          // between blocks
    static let listSpacing: CGFloat = 4       // between list items
    static let indent: CGFloat = 24           // per list level
    static let bullets = ["•", "◦", "▪"]
    static let codeBackground = NSColor.quaternarySystemFill

    static func heading(_ level: Int) -> NSFont {
        let sizes: [CGFloat] = [28, 22, 18, 16, 15, 14]
        return .systemFont(ofSize: sizes[max(0, min(5, level - 1))], weight: .bold)
    }

    static func code(matching font: NSFont) -> NSFont {
        .monospacedSystemFont(ofSize: (font.pointSize * 0.88).rounded(), weight: .regular)
    }
}

extension NSFont {
    func adding(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(trait))
        if let font = NSFont(descriptor: descriptor, size: pointSize),
           font.fontDescriptor.symbolicTraits.contains(trait) {
            return font
        }
        // Fallback for faces the descriptor path cannot resolve (e.g. italic system font).
        let mask: NSFontTraitMask = trait.contains(.bold) ? .boldFontMask : .italicFontMask
        return NSFontManager.shared.convert(self, toHaveTrait: mask)
    }
}

// MARK: - Visitor

/// Walks the swift-markdown tree and appends styled runs. Block visitors return paragraphs
/// terminated by "\n"; inline visitors return runs carrying only font/colour attributes.
struct Visitor: MarkupVisitor {
    typealias Result = NSAttributedString

    let baseURL: URL?

    // Inline state
    var font: NSFont = Style.body
    var color: NSColor = .textColor
    // Block state
    var alignment: NSTextAlignment = .natural
    var listDepth = 0
    var blocks: [NSTextBlock] = []            // enclosing quote / code / table-cell blocks
    var marker: NSAttributedString?           // list marker waiting for the item's first paragraph

    init(baseURL: URL?) { self.baseURL = baseURL }

    var attributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: color] }

    mutating func defaultVisit(_ markup: any Markup) -> NSAttributedString {
        visitChildren(markup)
    }

    mutating func visitChildren(_ markup: any Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children { result.append(visit(child)) }
        return result
    }

    // MARK: Helpers

    func paragraphStyle(spacingBefore: CGFloat = 0,
                        spacing: CGFloat = Style.spacing,
                        lineHeightMultiple: CGFloat = 1.2,
                        hanging: Bool = false) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacing
        style.lineHeightMultiple = lineHeightMultiple
        style.alignment = alignment
        style.textBlocks = blocks
        let indent = Style.indent * CGFloat(listDepth)
        style.headIndent = indent
        style.firstLineHeadIndent = hanging ? indent - Style.indent : indent
        style.tabStops = hanging ? [NSTextTab(textAlignment: .left, location: indent)] : []
        style.defaultTabInterval = Style.indent
        return style
    }

    /// Terminates `content` with "\n" and applies `style` to the whole paragraph.
    func paragraph(_ content: NSAttributedString, style: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: content)
        let terminatorAttributes = content.length > 0
            ? content.attributes(at: content.length - 1, effectiveRange: nil)
            : attributes
        result.append(NSAttributedString(string: "\n", attributes: terminatorAttributes))
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    mutating func withFont(_ newFont: NSFont, _ body: (inout Visitor) -> NSAttributedString) -> NSAttributedString {
        let saved = font
        font = newFont
        defer { font = saved }
        return body(&self)
    }

    /// Overrides the paragraph spacing of the last paragraph in `text` (used to close lists/quotes).
    func setSpacingAfter(_ text: NSMutableAttributedString, _ spacing: CGFloat) {
        guard text.length > 0 else { return }
        let range = (text.string as NSString).paragraphRange(for: NSRange(location: text.length - 1, length: 0))
        guard let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
              let mutable = style.mutableCopy() as? NSMutableParagraphStyle else { return }
        mutable.paragraphSpacing = spacing
        text.addAttribute(.paragraphStyle, value: mutable, range: range)
    }

    // MARK: Blocks

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let content = NSMutableAttributedString()
        let hanging = marker != nil
        if let marker { content.append(marker); self.marker = nil }
        content.append(visitChildren(paragraph))
        let spacing = listDepth > 0 ? Style.listSpacing : Style.spacing
        return self.paragraph(content, style: paragraphStyle(spacing: spacing, hanging: hanging))
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        withFont(Style.heading(heading.level)) { visitor in
            let content = visitor.visitChildren(heading)
            let before: CGFloat = heading.level == 1 ? 20 : 16
            return visitor.paragraph(content, style: visitor.paragraphStyle(spacingBefore: before, spacing: 8))
        }
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) -> NSAttributedString {
        NSAttributedString(string: text.string, attributes: attributes)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: attributes)
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\u{2028}", attributes: attributes)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        withFont(font.adding(.italic)) { $0.visitChildren(emphasis) }
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        withFont(font.adding(.bold)) { $0.visitChildren(strong) }
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let content = NSMutableAttributedString(attributedString: visitChildren(strikethrough))
        content.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                             range: NSRange(location: 0, length: content.length))
        return content
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSAttributedString {
        NSAttributedString(string: inlineHTML.rawHTML, attributes: attributes)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        let text = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = NSAttributedString(string: text, attributes: [.font: Style.code(matching: font),
                                                                     .foregroundColor: NSColor.secondaryLabelColor])
        return paragraph(content, style: paragraphStyle())
    }
}
