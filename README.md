# mdview

A tiny native macOS viewer for `.md` / `.markdown` files. Double-click a Markdown file, see it rendered. Live-reloads when the file changes on disk.

## Build

Open `mdview.xcodeproj` in Xcode 16+ and run, or:

    xcodebuild -project mdview.xcodeproj -scheme mdview -destination 'platform=macOS' -derivedDataPath build build

The project file is generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate`); regenerate it if you add files.

## Use

- Double-click a `.md` file in Finder (choose mdview under *Open With* the first time), or
- select a `.md` file in Finder and press **Space** — the bundled Quick Look extension renders it (launch the app once so macOS registers the extension), or
- `open -a mdview README.md`, or
- drag a file onto the window or Dock icon, or `File → Open…`.

The sidebar lists the document's headings (click to jump). The toolbar has zoom (⌘+ / ⌘− / ⌘0), a raw-source toggle, file info, Share, and Search (⌘F, ⌘G / ⇧⌘G for next / previous). Text is selectable and copyable, links open in your browser, dark mode follows the system.

Rendering matches GitHub: tables, task lists, syntax-highlighted code, Mermaid diagrams, autolinked URLs, clickable tables of contents, local and remote images.

Requires macOS 15 (Liquid Glass toolbar groups on macOS 26). No Swift package dependencies; the renderer is a bundled web page using [markdown-it](https://github.com/markdown-it/markdown-it), [highlight.js](https://highlightjs.org), [mermaid](https://mermaid.js.org) and [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) (all vendored under `MarkdownPreview/Resources/vendor`, no network access needed).

## Layout

    mdview/
    ├── MDViewApp.swift            DocumentGroup(viewing:) + Find menu
    ├── ContentView.swift          NavigationSplitView (outline sidebar + viewer), Preview-style toolbar, drop target
    ├── Viewer.swift               ViewerWebView (WKWebView) + Page — shared with the Quick Look extension
    ├── Document.swift             FileDocument + FileWatcher (live reload)
    ├── Resources/
    │   ├── viewer.html/.css/.js   the page: markdown-it setup, task lists, heading ids, find/highlight, raw mode
    │   └── vendor/                markdown-it, highlight.js, mermaid, github-markdown-css
    ├── Assets.xcassets            app icon
    └── Sample.md                  element gallery for manual testing
    mdviewQuickLook/               Quick Look preview extension (sandboxed; reuses Viewer.swift + Resources)
