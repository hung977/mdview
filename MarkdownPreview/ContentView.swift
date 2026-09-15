import SwiftUI
import AppKit

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    @State private var text: String
    @State private var watcher: FileWatcher?

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _text = State(initialValue: document.text)
    }

    var body: some View {
        MarkdownTextView(text: text, baseURL: fileURL?.deletingLastPathComponent())
            .onAppear {
                guard watcher == nil, let fileURL else { return }
                watcher = FileWatcher(url: fileURL) { reload(from: fileURL) }
            }
    }

    private func reload(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }   // mid-save; next event re-reads
        text = MarkdownDocument.decode(data)
    }
}

// MARK: - AppKit text view

struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let baseURL: URL?

    final class Coordinator {
        var lastText: String?
        var lastBaseURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        // Explicit TextKit 1 stack: NSTextTable/NSTextBlock are not supported by TextKit 2.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = ReadingTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        textView.frame.size.width = scrollView.contentSize.width

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ReadingTextView,
              context.coordinator.lastText != text || context.coordinator.lastBaseURL != baseURL else { return }
        context.coordinator.lastText = text
        context.coordinator.lastBaseURL = baseURL

        let offset = scrollView.contentView.bounds.origin
        textView.textStorage?.setAttributedString(MarkdownRenderer.render(text, baseURL: baseURL))
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.scroll(offset)
    }
}

/// Non-editable text view whose text column is centred at Style.maxWidth.
final class ReadingTextView: NSTextView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let horizontal = max(24, (newSize.width - Style.maxWidth) / 2)
        if textContainerInset.width != horizontal {
            textContainerInset = NSSize(width: horizontal, height: 32)
        }
    }
}
