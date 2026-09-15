<p align="center">
  <img src="docs/images/icon.png" width="128" alt="MDViewer icon">
</p>

<h1 align="center">MDViewer</h1>

<p align="center">
  A small, native macOS viewer for Markdown files — open, read, done.<br>
  Renders like GitHub, looks like Preview.app, reloads when the file changes.
</p>

<p align="center">
  <a href="https://github.com/hung977/mdview/releases/latest"><img src="https://img.shields.io/github/v/release/hung977/mdview?label=download" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT"></a>
</p>

## Features

- **GitHub-flavoured rendering** — CommonMark plus tables, task lists, strikethrough, autolinked URLs, clickable tables of contents, local and remote images, raw HTML.
- **Code & diagrams** — syntax highlighting (highlight.js) and Mermaid diagrams, loaded only when a document uses them.
- **Preview.app-style window** — outline sidebar, Liquid Glass toolbar with zoom, raw-source toggle, file info inspector, Share, and search with match count and highlighting.
- **Live reload** — edit the file in any editor, save, and the preview updates in place without losing your scroll position.
- **Quick Look** — select a `.md` file in Finder and press Space.
- **Native** — light/dark mode, text selection and copy, links open in your browser, document tabs, Open Recent, drag & drop onto the window or Dock icon.
- **Offline & self-contained** — every renderer dependency is bundled; the app makes no network requests except to load remote images you reference.

## Install

1. Download `MDViewer-<version>.zip` from the [latest release](https://github.com/hung977/mdview/releases/latest).
2. Unzip and move `MDViewer.app` to `/Applications`.
3. The app is signed ad hoc (not notarized), so allow it once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/MDViewer.app
   ```

   or right-click the app → **Open**.
4. Launch it once so macOS registers the file association and the Quick Look extension. On first launch MDViewer offers to become the default app for Markdown files; you can also do that later from the **MDViewer** menu.

## Usage

| Action | How |
|---|---|
| Open a file | double-click in Finder, drag onto the window or Dock icon, `File ▸ Open…`, or `open -a MDViewer README.md` |
| Quick Look | select a `.md` file in Finder and press **Space** |
| Outline | toolbar sidebar button; click a heading to jump to it |
| Find | **⌘F** to focus search, **⌘G** / **⇧⌘G** next / previous, **Enter** in the field for next |
| Zoom | **⌘+** / **⌘−** / **⌘0** (or the toolbar buttons; the middle one shows the current level) |
| Raw source | toolbar toggle — shows the Markdown as written, outline still works |
| File info | toolbar **ⓘ** — name, location, size, dates, words, characters, lines, headings, links, images, tables, code blocks, diagrams |

Supported extensions: `.md`, `.markdown`.

## Build from source

Requirements: macOS 15+, Xcode 26, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the `.xcodeproj` is generated from `project.yml`.

```sh
git clone https://github.com/hung977/mdview.git
cd mdview
make            # Debug build (generates the Xcode project if needed)
make test       # unit tests
make release    # Release build → dist/MDViewer.app and dist/MDViewer-<version>.zip
make install    # copy the Release build to /Applications and register Quick Look
```

Or open `mdview.xcodeproj` in Xcode after `xcodegen generate`.

## How it works

The app is a SwiftUI `DocumentGroup(viewing:)` shell around a single `WKWebView`. The web view hosts a bundled page that renders Markdown with [markdown-it](https://github.com/markdown-it/markdown-it) (GFM: tables, strikethrough, linkify, plus small custom rules for task lists and GitHub-style heading ids), highlights code with [highlight.js](https://highlightjs.org), draws diagrams with [mermaid](https://mermaid.js.org), and styles everything with [github-markdown-css](https://github.com/sindresorhus/github-markdown-css). Re-renders replace the document body in place, so live reload keeps the scroll position; search uses the CSS Custom Highlight API so it never touches the selection.

A `DispatchSource` watches the open file (including atomic saves that replace the inode). The Quick Look extension reuses the same web view and page, sandboxed. HTML embedded in a document is rendered but cannot run scripts (CSP with a per-process nonce).

```
mdview/                     app sources (module `mdview`)
├── MDViewApp.swift         DocumentGroup, Find / View menu commands
├── ContentView.swift       NavigationSplitView (outline + viewer), toolbar, info inspector, drop target
├── Viewer.swift            ViewerWebView (WKWebView) + Page — shared with the Quick Look extension
├── Document.swift          FileDocument + FileWatcher (live reload)
├── Resources/
│   ├── viewer.html/.css/.js   the page: markdown-it setup, outline, find/highlight, raw mode
│   └── vendor/                markdown-it, highlight.js, mermaid, github-markdown-css
└── Assets.xcassets         app icon
mdviewQuickLook/            Quick Look preview extension
mdviewTests/                XCTest: rendering via the real page (DOM and pixel checks), file watcher
```

## Known limitations

- Not notarized — first launch needs the `xattr` step above.
- Quick Look previews run in a sandbox that cannot read files next to the document, so local images show their alt text there (they display normally in the app).
- Search matches text within a single text node; a phrase spanning bold/italic boundaries is not matched.
- Liquid Glass toolbar groups need macOS 26; on macOS 15 the same items appear in a standard toolbar.

## License

[MIT](LICENSE). Bundled third-party code is also MIT-licensed: markdown-it, highlight.js, mermaid, github-markdown-css.
