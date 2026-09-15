import AppKit
import Markdown

enum MarkdownRenderer {
    static func render(_ markdown: String, baseURL: URL?) -> NSAttributedString {
        NSAttributedString(string: Document(parsing: markdown).format())
    }
}
