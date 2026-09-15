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

    // MARK: Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSAttributedString {
        let bullet = Style.bullets[listDepth % Style.bullets.count]
        return renderList(list) { _ in bullet }
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSAttributedString {
        let start = Int(list.startIndex)
        return renderList(list) { index in "\(start + index)." }
    }

    private mutating func renderList(_ list: any ListItemContainer, markerFor: (Int) -> String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        listDepth += 1
        for (index, item) in list.listItems.enumerated() {
            if let checkbox = item.checkbox {
                marker = checkboxMarker(checked: checkbox == .checked)
            } else {
                marker = NSAttributedString(string: markerFor(index) + "\t", attributes: attributes)
            }
            // Items whose first child is not a paragraph (nested list, code block, empty item)
            // get the marker on its own line so it is never lost.
            if !(item.child(at: 0) is Paragraph), let marker {
                result.append(paragraph(marker, style: paragraphStyle(spacing: Style.listSpacing, hanging: true)))
                self.marker = nil
            }
            result.append(visitChildren(item))
        }
        listDepth -= 1
        if listDepth == 0 { setSpacingAfter(result, Style.spacing) }
        return result
    }

    private func checkboxMarker(checked: Bool) -> NSAttributedString {
        let name = checked ? "checkmark.square.fill" : "square"
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(.init(paletteColors: [checked ? .controlAccentColor : .secondaryLabelColor]))
        let attachment = NSTextAttachment()
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: checked ? "checked" : "unchecked")?
            .withSymbolConfiguration(configuration) {
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: font.descender, width: image.size.width, height: image.size.height)
        }
        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "\t"))
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        return result
    }

    // MARK: Quote / rule

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let block = NSTextBlock()
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(.separatorColor)
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(Style.spacing, type: .absoluteValueType, for: .margin, edge: .maxY)
        blocks.append(block)
        let savedColor = color
        color = .secondaryLabelColor
        defer { blocks.removeLast(); color = savedColor }
        let content = NSMutableAttributedString(attributedString: visitChildren(blockQuote))
        setSpacingAfter(content, 0)   // the block margin provides the gap
        return content
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        let block = NSTextBlock()
        block.backgroundColor = .separatorColor
        block.setValue(1, type: .absoluteValueType, for: .height)
        block.setValue(1, type: .absoluteValueType, for: .maximumHeight)
        block.setWidth(Style.spacing, type: .absoluteValueType, for: .margin, edge: .minY)
        block.setWidth(Style.spacing, type: .absoluteValueType, for: .margin, edge: .maxY)
        blocks.append(block)
        defer { blocks.removeLast() }
        let hairline = NSAttributedString(string: "\u{200B}", attributes: [.font: NSFont.systemFont(ofSize: 1)])
        return paragraph(hairline, style: paragraphStyle(spacing: 0, lineHeightMultiple: 1))
    }

    // MARK: Code

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSAttributedString {
        NSAttributedString(string: inlineCode.code, attributes: [
            .font: Style.code(matching: font),
            .foregroundColor: color,
            .backgroundColor: Style.codeBackground,
        ])
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        let block = NSTextBlock()
        block.backgroundColor = Style.codeBackground
        block.setWidth(12, type: .absoluteValueType, for: .padding)
        block.setWidth(Style.spacing, type: .absoluteValueType, for: .margin, edge: .maxY)
        blocks.append(block)
        defer { blocks.removeLast() }

        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }
        let text = NSMutableAttributedString(string: code + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ])
        CodeHighlighter.highlight(text, language: codeBlock.language)
        text.addAttribute(.paragraphStyle, value: paragraphStyle(spacing: 0, lineHeightMultiple: 1.15),
                          range: NSRange(location: 0, length: text.length))
        return text
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) -> NSAttributedString {
        let columns = table.maxColumnCount
        guard columns > 0 else { return NSAttributedString() }

        var rows: [[Table.Cell]] = [table.head.children.compactMap { $0 as? Table.Cell }]
        for row in table.body.children.compactMap({ $0 as? Table.Row }) {
            rows.append(row.children.compactMap { $0 as? Table.Cell })
        }

        let textTable = NSTextTable()
        textTable.numberOfColumns = columns
        textTable.collapsesBorders = true
        textTable.setWidth(Style.spacing, type: .absoluteValueType, for: .margin, edge: .maxY)
        let (percentages, naturalWidth) = columnPercentages(rows, columns: columns)
        textTable.setValue(min(100, naturalWidth / Style.maxWidth * 100), type: .percentageValueType, for: .width)

        let result = NSMutableAttributedString()
        let savedAlignment = alignment
        defer { alignment = savedAlignment }
        for (rowIndex, row) in rows.enumerated() {
            for column in 0 ..< columns {
                let block = NSTextTableBlock(table: textTable, startingRow: rowIndex, rowSpan: 1,
                                             startingColumn: column, columnSpan: 1)
                block.setBorderColor(.separatorColor)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                block.setValue(percentages[column], type: .percentageValueType, for: .width)
                if rowIndex == 0 { block.backgroundColor = Style.codeBackground }
                blocks.append(block)
                switch column < table.columnAlignments.count ? table.columnAlignments[column] : nil {
                case .center: alignment = .center
                case .right: alignment = .right
                default: alignment = .left
                }
                let content: NSAttributedString
                if column < row.count {
                    content = rowIndex == 0
                        ? withFont(font.adding(.bold)) { $0.visitChildren(row[column]) }
                        : visitChildren(row[column])
                } else {
                    content = NSAttributedString()
                }
                result.append(paragraph(content, style: paragraphStyle(spacing: 0)))
                blocks.removeLast()
            }
        }
        return result
    }

    /// Natural width of each column (measured plain text + padding) as percentages of the table,
    /// plus the table's total natural width in points.
    private func columnPercentages(_ rows: [[Table.Cell]], columns: Int) -> ([CGFloat], CGFloat) {
        var widths = [CGFloat](repeating: 24, count: columns)
        for row in rows {
            for (column, cell) in row.prefix(columns).enumerated() {
                let measured = (cell.plainText as NSString).size(withAttributes: [.font: Style.body]).width + 16
                widths[column] = max(widths[column], min(measured, Style.maxWidth / 2))
            }
        }
        let total = widths.reduce(0, +)
        return (widths.map { $0 / total * 100 }, total)
    }

    // MARK: Links & images

    mutating func visitLink(_ link: Link) -> NSAttributedString {
        let content = NSMutableAttributedString(attributedString: visitChildren(link))
        if let url = resolve(link.destination) {
            content.addAttribute(.link, value: url, range: NSRange(location: 0, length: content.length))
        }
        return content
    }

    mutating func visitImage(_ image: Image) -> NSAttributedString {
        let alt = NSAttributedString(string: image.plainText,
                                     attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        guard let url = resolve(image.source) else { return alt }
        let attachment: ImageAttachment
        if url.isFileURL {
            guard let loaded = NSImage(contentsOf: url) else { return alt }
            attachment = ImageAttachment(image: loaded)
        } else {
            attachment = ImageAttachment(remote: url)
        }
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Absolute URLs pass through; relative paths resolve against the document's folder;
    /// fragment-only links are dropped.
    func resolve(_ destination: String?) -> URL? {
        guard let destination, !destination.isEmpty, !destination.hasPrefix("#") else { return nil }
        if let url = URL(string: destination), url.scheme != nil { return url }
        guard let baseURL else { return nil }
        let path = String(destination.split(separator: "#", maxSplits: 1)[0])
        return URL(fileURLWithPath: path.removingPercentEncoding ?? path, relativeTo: baseURL).absoluteURL
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
        // `<br>` is ubiquitous inside table cells; everything else stays literal.
        let isLineBreak = inlineHTML.rawHTML.range(of: #"^<br\s*/?>$"#, options: [.regularExpression, .caseInsensitive]) != nil
        return NSAttributedString(string: isLineBreak ? "\u{2028}" : inlineHTML.rawHTML, attributes: attributes)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        let text = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = NSAttributedString(string: text, attributes: [.font: Style.code(matching: font),
                                                                     .foregroundColor: NSColor.secondaryLabelColor])
        return paragraph(content, style: paragraphStyle())
    }
}

// MARK: - Code highlighting

/// Deliberately tiny: comments, strings, numbers and a shared keyword list. No grammars.
enum CodeHighlighter {
    private static let plainLanguages: Set<String> = ["text", "plain", "plaintext", "txt", "markdown", "md", "output", "console"]
    private static let hashLanguages: Set<String> = ["python", "py", "ruby", "rb", "sh", "bash", "zsh", "shell", "fish",
                                                     "yaml", "yml", "toml", "ini", "conf", "dockerfile", "makefile",
                                                     "make", "r", "perl", "pl", "elixir", "ex", "nim", "powershell", "ps1"]
    private static let dashLanguages: Set<String> = ["sql", "lua", "haskell", "hs", "elm", "ada"]
    private static let markupLanguages: Set<String> = ["html", "xml", "svg", "vue", "xhtml", "plist"]

    private static let keywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "def", "default", "defer",
        "do", "elif", "else", "enum", "except", "export", "extends", "extension", "false", "fn", "for", "from",
        "func", "function", "guard", "if", "impl", "import", "in", "init", "interface", "internal", "is", "let",
        "match", "mod", "module", "mut", "new", "nil", "none", "not", "null", "or", "and", "package", "pass",
        "private", "protocol", "pub", "public", "raise", "return", "self", "static", "struct", "super", "switch",
        "then", "this", "throw", "throws", "trait", "true", "try", "type", "typealias", "undefined", "use", "var",
        "void", "when", "where", "while", "with", "yield", "select", "insert", "update", "delete", "create", "table",
        "join", "into", "values", "end", "begin", "local", "require", "elseif", "lambda", "override", "final",
        "some", "any", "int", "string", "bool", "float", "double", "char", "long", "unsigned", "using", "namespace",
    ]

    static func highlight(_ text: NSMutableAttributedString, language: String?) {
        guard let language = language?.lowercased().trimmingCharacters(in: .whitespaces),
              !language.isEmpty, !plainLanguages.contains(language) else { return }

        let comment: String
        if hashLanguages.contains(language) { comment = #"#[^\n]*"# }
        else if dashLanguages.contains(language) { comment = #"--[^\n]*"# }
        else if markupLanguages.contains(language) { comment = #"<!--[\s\S]*?-->"# }
        else { comment = #"//[^\n]*|/\*[\s\S]*?\*/"# }

        let passes: [(pattern: String, color: NSColor)] = [
            (comment, .secondaryLabelColor),
            (#""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`[^`\n]*`"#, .systemRed),
            (#"\b\d+(?:\.\d+)?\b"#, .systemBlue),
            (#"\b(?:"# + keywords.sorted().joined(separator: "|") + #")\b"#, .systemPurple),
        ]

        let string = text.string as NSString
        let full = NSRange(location: 0, length: string.length)
        var covered = [Bool](repeating: false, count: string.length)
        for pass in passes {
            guard let regex = try? NSRegularExpression(pattern: pass.pattern) else { continue }
            for match in regex.matches(in: text.string, range: full) {
                let range = match.range
                guard range.length > 0, !covered[range.location] else { continue }
                text.addAttribute(.foregroundColor, value: pass.color, range: range)
                for i in range.location ..< range.location + range.length { covered[i] = true }
            }
        }
    }
}

// MARK: - Images

/// Attachment that scales to the line width and, for remote URLs, fills itself in when the
/// download finishes. A small in-memory cache keeps live reloads from re-downloading.
final class ImageAttachment: NSTextAttachment {
    private static var cache: [URL: NSImage] = [:]   // main-thread only

    private weak var layoutManager: NSLayoutManager?
    private var characterIndex = NSNotFound

    init(image: NSImage?) {
        super.init(data: nil, ofType: nil)
        self.image = image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    convenience init(remote url: URL) {
        self.init(image: Self.cache[url])
        guard image == nil else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let loaded = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                if let loaded { Self.cache[url] = loaded }
                self?.didLoad(loaded ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "missing image"))
            }
        }.resume()
    }

    private func didLoad(_ loaded: NSImage?) {
        image = loaded
        guard let storage = layoutManager?.textStorage, characterIndex < storage.length else { return }
        storage.edited(.editedAttributes, range: NSRange(location: characterIndex, length: 1), changeInLength: 0)
    }

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        layoutManager = textContainer?.layoutManager
        characterIndex = charIndex
        guard let image, image.size.width > 0 else { return .zero }
        let available = max(1, lineFrag.width - 2 * (textContainer?.lineFragmentPadding ?? 0))
        let scale = min(1, available / image.size.width)
        return CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
    }
}
