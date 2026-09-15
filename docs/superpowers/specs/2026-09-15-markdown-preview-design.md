# Markdown Preview — Design

A tiny native macOS viewer for `.md` / `.markdown` files. Double-click in Finder → rendered Markdown. A viewer, not an editor.

Priority: simplicity > reliability > native feel > features.

## Decisions

- **Engine:** Apple `swift-markdown` (cmark-gfm) → hand-written `NSAttributedString` renderer → `NSTextView`. Chosen over WKWebView (extra process, non-native find) and swift-markdown-ui (no native find/selection, slow on long docs). Foundation `AttributedString(markdown:)` was rejected: no tables, task lists, images, block code, or highlighting.
- **Only dependency:** `apple/swift-markdown` via SPM (pulls `swift-cmark`).
- **Target:** macOS 14+, Swift 5, SwiftUI app shell, AppKit text view.
- **TextKit 1** explicitly. `NSTextTable`/`NSTextBlock` are not supported by TextKit 2, so the text view is created on an explicit `NSTextStorage → NSLayoutManager → NSTextContainer` stack.
- **No App Sandbox:** the sandbox would block reading images stored next to the opened file (a required feature). Ad-hoc signing, hardened runtime.
- **Project generation:** `project.yml` for `xcodegen`; the generated `MarkdownPreview.xcodeproj` is committed so the project opens and builds immediately.

## Layout

```
MarkdownPreview/
├── project.yml
├── MarkdownPreview.xcodeproj            (generated)
├── MarkdownPreview/
│   ├── MarkdownPreviewApp.swift         DocumentGroup(viewing:)
│   ├── Document.swift                   MarkdownDocument (FileDocument) + FileWatcher
│   ├── ContentView.swift                NSViewRepresentable around NSScrollView/NSTextView, drop target
│   ├── MarkdownRenderer.swift           MarkupVisitor → NSAttributedString, tiny highlighter
│   ├── Info.plist                       CFBundleDocumentTypes for .md/.markdown (Viewer)
│   └── Sample.md                        element gallery for manual testing (not bundled)
└── MarkdownPreviewTests/
    └── MarkdownRendererTests.swift
```

No MVVM, no coordinators, no DI. Four source files.

## Components

### MarkdownPreviewApp
`DocumentGroup(viewing: MarkdownDocument.self) { ContentView(document:, fileURL:) }`. This alone provides: File → Open (⌘O), Open Recent, Open panel at launch when no document is given (Preview.app behaviour), window title = filename, Dock-icon drop, Launch Services handoff for double-click and `open -a "Markdown Preview" file.md`. No custom commands; the default Edit menu already contains Find (⌘F) which drives the text view's find bar.

### Document.swift
- `MarkdownDocument: FileDocument` — `readableContentTypes = [UTType("net.daringfireball.markdown")]` — declared in Info.plist as an imported type (`UTImportedTypeDeclarations`, extensions `md`/`markdown`, conforms to `public.plain-text`) since there is no system-provided Markdown UTType constant, `text: String` decoded as UTF‑8 (fallback: Latin‑1 so nothing fails to open). `fileWrapper(configuration:)` throws — never called in viewing mode.
- `FileWatcher` — `final class` holding a `DispatchSourceFileSystemObject` on `open(path, O_EVTONLY)`, mask `.write | .delete | .rename | .extend`. Fires `onChange()` on the main queue. On `.delete`/`.rename` (atomic saves by VS Code etc.) it cancels and re-arms after 100 ms if the path exists again. `deinit` cancels the source (which closes the fd in the cancel handler).

### ContentView.swift
- SwiftUI `struct ContentView: View` holding `@State var text` seeded from the document, a `FileWatcher` created in `.onAppear`/`.task` for `fileURL`, and `.onDrop(of: [.fileURL])` that calls `NSDocumentController.shared.openDocument(withContentsOf:display:true)` for each dropped `.md`/`.markdown` URL.
- `MarkdownTextView: NSViewRepresentable` — `makeNSView` builds the TextKit 1 stack inside an `NSScrollView`; `updateNSView` re-renders when `text` or `baseURL` changes, replacing `textStorage` contents while preserving the scroll offset.
- `ReadingTextView: NSTextView` subclass — non-editable, selectable, `usesFindBar = true`, `isIncrementalSearchingEnabled = true`, `drawsBackground` with `.textBackgroundColor`. Overrides `setFrameSize(_:)` to set `textContainerInset = (max(24, (width − 720)/2), 32)` so the column is centred with a max reading width of 720 pt.

### MarkdownRenderer.swift
`struct MarkdownRenderer` with `static func render(_ markdown: String, baseURL: URL?) -> NSAttributedString`. Implemented as a `MarkupVisitor` producing `NSAttributedString` per node.

| Markdown | Rendering |
|---|---|
| Headings 1–6 | Bold system font 28/22/18/16/15/14 pt, extra paragraph spacing before |
| Paragraph | 15 pt system font, line height multiple 1.35, 12 pt paragraph spacing |
| Emphasis / strong / strikethrough | Font trait italic / bold, `.strikethroughStyle` |
| Inline code | `NSFont.monospacedSystemFont(13)` + `quaternaryLabelColor` background |
| Fenced / indented code | Full-width `NSTextBlock` (padding 12, background `quaternaryLabelColor`), monospaced 13 pt, no wrapping concerns (wraps normally) |
| Lists | `NSParagraphStyle` with `headIndent`/`firstLineHeadIndent` = 24 pt × depth and a tab stop; bullets `•`, `◦`, `▪` by depth; ordered = `n.` honoring start index |
| Task list items | SF Symbol attachment `square` / `checkmark.square` in place of the bullet |
| Blockquote | `NSTextBlock` with 3 pt left border in `separatorColor`, 12 pt left padding, text in `secondaryLabelColor` |
| Links | `.link` attribute with the resolved URL (relative → against `baseURL`) |
| Images | `NSTextAttachment`. File URLs load synchronously; `http(s)` fetched with `URLSession`, attachment image set on arrival and layout invalidated. Width capped to 720 pt preserving aspect. Failure → alt text in `secondaryLabelColor` |
| Tables | `NSTextTable`, header row bold, `NSTextTableBlock` per cell with 1 pt `separatorColor` borders and 6 pt padding, `collapsesBorders = true`, column alignment honoured |
| Thematic break | Paragraph containing a single space with a 1 pt-tall `NSTextBlock` whose background is `separatorColor` |
| Soft/line break | space / `\n` |
| HTML blocks / inline HTML | Rendered as plain monospaced text (no HTML interpretation) |

All colours are semantic `NSColor`s, so light/dark mode resolve at draw time and switch live.

**Syntax highlighting** — `enum CodeHighlighter { static func highlight(_ code: NSMutableAttributedString, language: String?) }`. One regex pass over: block/line comments (`//`, `#`, `/* */`, `<!-- -->`, `--`), string literals (`"…"`, `'…'`, `` `…` ``), numbers, and a single shared keyword set (`func let var if else for while return import class struct enum def fn const function true false nil null …`). Four colours: comment `secondaryLabelColor`, string `systemRed`, number `systemBlue`, keyword `systemPurple`. No per-language grammars; unknown languages get the same pass; `language == "text"/"plain"` skips it.

## Data flow

1. Launch Services / Open panel / drop → `DocumentGroup` → `MarkdownDocument.init(configuration:)` reads bytes once → `ContentView`.
2. `ContentView` renders `text` into `NSTextStorage` (the only retained copy of the rendered document; the `String` in the document struct is the source).
3. `FileWatcher` event → re-read file → `text` changes → `updateNSView` re-renders and swaps storage, restoring the previous scroll offset (clamped).

## Error handling

- Unreadable file: `FileDocument` init throws → SwiftUI shows the standard alert.
- Watcher re-read failure (file momentarily missing during an atomic save): ignore, keep last render; the follow-up event re-reads.
- Missing / undecodable image: alt text.
- Malformed Markdown never fails — cmark always produces a tree.

## Testing

- **Unit (XCTest, `MarkdownRendererTests`)**: render small snippets and assert on attributes: H1 font size; strong is bold; inline code font is monospaced; table paragraph has an `NSTextTableBlock`; link attribute resolved against `baseURL`; task item contains an attachment; code block gets a comment-coloured run; thematic break exists. `FileWatcher` test: write temp file, mutate, expect callback; atomic replace (write temp + rename), expect callback.
- **Manual checklist**: open via Finder double-click, ⌘O, drag onto window and Dock; dark mode toggle; edit `Sample.md` in another editor and save; scroll, select, copy, ⌘F, click link; check every element in `Sample.md`.

## Out of scope

Editing, preferences, custom windows/toolbar, remote-image caching, per-language grammars, TextKit 2, HTML rendering, math, footnotes styling beyond plain text, printing.

---

## Revision 2 (2026-09-15): WKWebView engine

After using the TextKit build on real documents the user rejected it (tables did not reflow with the
window, bare URLs and table-of-contents anchors were not links, no diagrams, rendering visibly worse
than GitHub). The engine was replaced; everything outside the rendering box is unchanged.

- **Engine:** `WKWebView` hosting a bundled page — `markdown-it` 14.1 (GFM + `linkify`, own rules for
  task lists and GitHub-style heading ids), `highlight.js` 11.11 (common languages),
  `mermaid` 11.12 (injected lazily only when the document has a ```` ```mermaid ```` fence),
  `github-markdown-css` 5.8 (light/dark via `prefers-color-scheme`). All vendored under
  `MarkdownPreview/Resources/vendor`; no network needed. `swift-markdown` dependency removed.
- **Page lifecycle:** the shell (`viewer.html` + inlined CSS/JS) is written once per process to a temp
  file and loaded with `loadFileURL(_:allowingReadAccessTo: "/")` so images next to the document load;
  a `<base href>` is set per document. Re-renders call `render(text, base)` in JS and replace
  `#content` in place, so live reload keeps the scroll position.
- **Security:** CSP with a per-process script nonce — HTML embedded in a Markdown file cannot run
  scripts or inline handlers; only images/fonts may be fetched.
- **Find:** a native AppKit find bar (`FindBar`: NSSearchField, ‹ › segmented control, Done; small controls
  like NSTextView's) stacked above the web view in `ViewerView`. Edit ▸ Find (⌘F / ⌘G / ⇧⌘G) targets the
  `ViewerView` in the key window. The page only searches and paints matches (`findSet/findNext/findPrevious/
  findClear` using the CSS Custom Highlight API), returning "3 of 12" for the bar. Both the bar and the web
  view own private `UndoManager`s so nothing marks the document "Edited".
- **Raw view:** a toolbar toggle (`doc.plaintext`) switches the page between rendered preview and the raw
  Markdown source (`setMode`).
- **Links:** in-page `#anchors` scroll via JS; `.md`/`.markdown` file links open in the app; anything
  else goes to `NSWorkspace`.
- **Layout:** `.markdown-body` centred, max-width 920 px, reflows with the window.
- **Files:** `MarkdownPreviewApp.swift`, `Document.swift`, `ContentView.swift` (ContentView,
  `MarkdownWebView`, `ViewerView`, `FindBar`, `ViewerWebView`, `Page`), `Resources/`. `MarkdownRenderer.swift` deleted.
- **Tests:** `ViewerWebViewTests` render through the real page and assert on the DOM; `FileWatcherTests` unchanged.
- **Cost:** one extra WebContent process (~140 MB on an 86 KB, 428-row document); window still appears in ~0.4 s.

## Revision 3 (2026-09-15): mdview, Quick Look, icon

- App renamed **mdview** (product, module, bundle id `com.hungpv.mdview`, targets `mdview`, `mdviewTests`, `mdviewQuickLook`).
- Title bar: `.windowToolbarStyle(.unifiedCompact)` — standard-height title bar like TextEdit, with the
  Raw/Preview toolbar toggle inline.
- Find bar is native AppKit (see Revision 2 note); the search field stretches across the bar.
- **Quick Look Preview Extension** (`mdviewQuickLook`, `com.apple.quicklook.preview`, content type
  `net.daringfireball.markdown`): a `QLPreviewingController` that hosts `ViewerWebView` and calls the
  completion handler after the page has rendered. Sandboxed with `files.user-selected.read-only` and
  `network.client` — the latter is required for WKWebView's processes to run inside a sandbox at all.
  Images next to the file are not readable from the sandbox, so Quick Look shows their alt text.
- `Viewer.swift` (ViewerWebView + Page) and `Resources/` are compiled into both the app and the extension;
  `Page` locates resources with `Bundle(for: ViewerWebView.self)`.
- App icon generated programmatically (blue squircle, Markdown "M↓" mark) into `Assets.xcassets/AppIcon`.
