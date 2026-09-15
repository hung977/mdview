import SwiftUI
import WebKit
import UniformTypeIdentifiers

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
        MarkdownWebView(text: text, baseURL: fileURL?.deletingLastPathComponent())
            .onAppear {
                guard watcher == nil, let fileURL else { return }
                watcher = FileWatcher(url: fileURL) { reload(from: fileURL) }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, ["md", "markdown"].contains(url.pathExtension.lowercased()) else { return }
                        DispatchQueue.main.async {
                            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                        }
                    }
                }
                return true
            }
    }

    private func reload(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }   // mid-save; next event re-reads
        text = MarkdownDocument.decode(data)
    }
}

// MARK: - WebKit host

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let baseURL: URL?

    final class Coordinator { var lastText: String? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ViewerView {
        ViewerView(baseURL: baseURL)
    }

    func updateNSView(_ viewer: ViewerView, context: Context) {
        guard context.coordinator.lastText != text else { return }
        context.coordinator.lastText = text
        viewer.webView.render(text)
    }
}

// MARK: - Viewer = native find bar + web view

/// Stacks a native find bar (hidden until ⌘F) above the web view, and puts the Raw/Preview toggle
/// in the window's title bar. The find actions from the Edit ▸ Find menu land here.
final class ViewerView: NSView {
    let webView: ViewerWebView
    let findBar = FindBar()
    let rawToggle = RawToggleAccessory()

    init(baseURL: URL?) {
        webView = ViewerWebView(baseURL: baseURL)
        super.init(frame: .zero)
        let stack = NSStackView(views: [findBar, webView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            findBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            webView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        findBar.isHidden = true
        findBar.onQueryChange = { [weak self] query in self?.run("findSet(\(FindBar.json(query)))") }
        findBar.onNext = { [weak self] in self?.findNext(nil) }
        findBar.onPrevious = { [weak self] in self?.findPrevious(nil) }
        findBar.onDone = { [weak self] in self?.hideFind() }
        rawToggle.onToggle = { [weak self] raw in self?.webView.setMode(raw: raw) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !window.titlebarAccessoryViewControllers.contains(rawToggle) else { return }
        window.addTitlebarAccessoryViewController(rawToggle)
    }

    static func first(in view: NSView) -> ViewerView? {
        if let found = view as? ViewerView { return found }
        for subview in view.subviews { if let found = first(in: subview) { return found } }
        return nil
    }

    @objc func showFind(_ sender: Any?) {
        findBar.isHidden = false
        window?.makeFirstResponder(findBar.field)
        findBar.field.selectText(nil)
        run("findSet(\(FindBar.json(findBar.field.stringValue)))")
    }

    @objc func findNext(_ sender: Any?) {
        if findBar.isHidden { showFind(sender) } else { run("findNext()") }
    }

    @objc func findPrevious(_ sender: Any?) {
        if findBar.isHidden { showFind(sender) } else { run("findPrevious()") }
    }

    func hideFind() {
        findBar.isHidden = true
        run("findClear()")
        window?.makeFirstResponder(webView)
    }

    /// Runs a find call in the page and shows the status it returns ("3 of 12", "Not found").
    private func run(_ script: String) {
        webView.evaluate(script) { [weak self] result in
            self?.findBar.status = result as? String ?? ""
        }
    }
}

/// A small toggle at the trailing edge of the standard title bar: rendered preview ⇄ raw source.
final class RawToggleAccessory: NSTitlebarAccessoryViewController {
    var onToggle: ((Bool) -> Void)?
    private let button = NSButton()

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .trailing
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func loadView() {
        button.image = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: "Raw Markdown")
        button.bezelStyle = .texturedRounded
        button.setButtonType(.pushOnPushOff)
        button.isBordered = true
        button.toolTip = "Show raw Markdown"
        button.target = self
        button.action = #selector(toggled)
        button.controlSize = .small
        button.sizeToFit()
        // Title bar accessories are sized from their frame, not from Auto Layout.
        let size = NSSize(width: max(button.frame.width, 30), height: max(button.frame.height, 22))
        button.frame = NSRect(origin: .zero, size: size)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 10, height: size.height))
        container.addSubview(button)
        view = container
    }

    var isRaw: Bool { button.state == .on }

    @objc private func toggled() {
        button.toolTip = isRaw ? "Show rendered preview" : "Show raw Markdown"
        onToggle?(isRaw)
    }
}

/// Small-control find bar modelled on NSTextView's: search field, count, ‹ ›, Done.
final class FindBar: NSView, NSSearchFieldDelegate {
    let field = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let arrows = NSSegmentedControl()
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onDone: (() -> Void)?

    var status: String = "" {
        didSet { countLabel.stringValue = status }
    }

    /// Typing must not reach the document's undo manager (that would mark the file "Edited").
    private let barUndoManager = UndoManager()
    override var undoManager: UndoManager? { barUndoManager }

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = "Find"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = self
        field.target = self
        field.action = #selector(queryChanged)
        field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)   // stretch to fill the bar

        countLabel.controlSize = .small
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .left
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        arrows.segmentCount = 2
        arrows.trackingMode = .momentary
        arrows.controlSize = .small
        arrows.segmentStyle = .rounded
        arrows.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous match"), forSegment: 0)
        arrows.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next match"), forSegment: 1)
        arrows.setWidth(28, forSegment: 0)
        arrows.setWidth(28, forSegment: 1)
        arrows.target = self
        arrows.action = #selector(arrowClicked)
        arrows.setContentHuggingPriority(.required, for: .horizontal)

        doneButton.controlSize = .small
        doneButton.bezelStyle = .rounded
        doneButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        doneButton.target = self
        doneButton.action = #selector(doneClicked)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [field, countLabel, arrows, doneButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: row.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @objc private func queryChanged() { onQueryChange?(field.stringValue) }
    @objc private func arrowClicked() { arrows.selectedSegment == 0 ? onPrevious?() : onNext?() }
    @objc private func doneClicked() { onDone?() }

    // Return / Shift-Return step through matches; Escape closes the bar.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrevious?() } else { onNext?() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDone?()
            return true
        default:
            return false
        }
    }

    static func json(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }
}
