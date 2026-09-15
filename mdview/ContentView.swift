import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    @State private var text: String
    @State private var watcher: FileWatcher?
    @State private var showRaw = false
    @State private var outline: [Heading] = []
    @State private var selectedHeading: Heading.ID?
    @State private var scrollRequest: ScrollRequest?

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _text = State(initialValue: document.text)
    }

    var body: some View {
        NavigationSplitView {
            List(outline, selection: $selectedHeading) { heading in
                Text(heading.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(heading.level <= 1 ? .body.weight(.semibold) : .body)
                    .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
            .overlay {
                if outline.isEmpty {
                    Text("No Headings").foregroundStyle(.secondary)
                }
            }
        } detail: {
            MarkdownWebView(text: text, baseURL: fileURL?.deletingLastPathComponent(), showRaw: showRaw,
                            scrollRequest: scrollRequest) { outline = $0 }
                .ignoresSafeArea(.container, edges: .top)   // page scrolls under the glass toolbar
                .toolbar {
                    ToolbarItem {
                        Toggle(isOn: $showRaw) {
                            Label("Raw", systemImage: "doc.plaintext")
                        }
                        .toggleStyle(.button)
                        .help(showRaw ? "Show rendered preview" : "Show raw Markdown")
                    }
                }
        }
        .onChange(of: selectedHeading) { _, id in
            guard let id else { return }
            scrollRequest = ScrollRequest(id: id)
        }
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

/// A sidebar click; a fresh value each time so re-selecting after scrolling away works too.
struct ScrollRequest: Equatable {
    let id: Heading.ID
    let token = UUID()
}

// MARK: - WebKit host

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let baseURL: URL?
    let showRaw: Bool
    let scrollRequest: ScrollRequest?
    let onOutline: ([Heading]) -> Void

    final class Coordinator {
        var lastText: String?
        var lastShowRaw = false
        var lastScrollRequest: ScrollRequest?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ViewerView {
        ViewerView(baseURL: baseURL)
    }

    func updateNSView(_ viewer: ViewerView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastShowRaw != showRaw {
            coordinator.lastShowRaw = showRaw
            viewer.webView.setMode(raw: showRaw)
        }
        if coordinator.lastText != text {
            coordinator.lastText = text
            let onOutline = onOutline
            viewer.webView.render(text) { outline in DispatchQueue.main.async { onOutline(outline) } }
        }
        if coordinator.lastScrollRequest != scrollRequest, let scrollRequest {
            coordinator.lastScrollRequest = scrollRequest
            viewer.webView.scrollToHeading(scrollRequest.id)
        }
    }
}

// MARK: - Viewer = native find bar + web view

/// Stacks a native find bar (hidden until ⌘F) above the web view. The find actions from the
/// Edit ▸ Find menu land here.
final class ViewerView: NSView {
    let webView: ViewerWebView
    let findBar = FindBar()

    private var findBarTop: NSLayoutConstraint!
    private var lastInset: CGFloat = -1

    init(baseURL: URL?) {
        webView = ViewerWebView(baseURL: baseURL)
        super.init(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        findBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        addSubview(findBar)
        findBarTop = findBar.topAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            findBarTop,
            findBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        findBar.isHidden = true
        findBar.onQueryChange = { [weak self] query in self?.run("findSet(\(FindBar.json(query)))") }
        findBar.onNext = { [weak self] in self?.findNext(nil) }
        findBar.onPrevious = { [weak self] in self?.findPrevious(nil) }
        findBar.onDone = { [weak self] in self?.hideFind() }
    }

    /// Keeps the find bar below the toolbar and tells the page how much chrome it scrolls under.
    override func layout() {
        super.layout()
        var chrome: CGFloat = 0
        if let window {
            let topInWindow = convert(bounds, to: nil).maxY
            chrome = max(0, topInWindow - window.contentLayoutRect.maxY)
        }
        findBarTop.constant = chrome
        let inset = chrome + (findBar.isHidden ? 0 : findBar.fittingSize.height)
        if inset != lastInset {
            lastInset = inset
            webView.evaluate("setTopInset(\(inset))") { _ in }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    static func first(in view: NSView) -> ViewerView? {
        if let found = view as? ViewerView { return found }
        for subview in view.subviews { if let found = first(in: subview) { return found } }
        return nil
    }

    @objc func showFind(_ sender: Any?) {
        findBar.isHidden = false
        needsLayout = true
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
        needsLayout = true
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

/// Small-control find bar modelled on NSTextView's: search field, count, ‹ ›, Done.
final class FindBar: NSVisualEffectView, NSSearchFieldDelegate {
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
        material = .headerView
        blendingMode = .withinWindow
        state = .followsWindowActiveState

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
