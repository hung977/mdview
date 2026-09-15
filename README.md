# Markdown Preview

A tiny native macOS viewer for `.md` / `.markdown` files. Double-click a Markdown file, see it rendered. Live-reloads when the file changes on disk.

## Build

Open `MarkdownPreview.xcodeproj` in Xcode 16+ and run, or:

    xcodebuild -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS' -derivedDataPath build build

The project file is generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate`); regenerate it if you add files.

## Use

- Double-click a `.md` file in Finder (choose Markdown Preview under *Open With* the first time), or
- `open -a "Markdown Preview" README.md`, or
- drag a file onto the window or Dock icon, or `File → Open…`.

⌘F finds, text is selectable and copyable, links open in your browser, dark mode follows the system.

Rendering matches GitHub: tables, task lists, syntax-highlighted code, Mermaid diagrams, autolinked URLs, clickable tables of contents, local and remote images.

Requires macOS 14. No Swift package dependencies; the renderer is a bundled web page using [markdown-it](https://github.com/markdown-it/markdown-it), [highlight.js](https://highlightjs.org), [mermaid](https://mermaid.js.org) and [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) (all vendored under `MarkdownPreview/Resources/vendor`, no network access needed).

## Layout

    MarkdownPreview/
    ├── MarkdownPreviewApp.swift   DocumentGroup(viewing:) + Find menu
    ├── ContentView.swift          WKWebView host (ViewerWebView), link handling, drop target
    ├── Document.swift             FileDocument + FileWatcher (live reload)
    ├── Resources/
    │   ├── viewer.html/.css/.js   the page: markdown-it setup, task lists, heading ids, find bar
    │   └── vendor/                markdown-it, highlight.js, mermaid, github-markdown-css
    └── Sample.md                  element gallery for manual testing
