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

Requires macOS 14. One dependency: [swift-markdown](https://github.com/apple/swift-markdown).

## Layout

    MarkdownPreview/
    ├── MarkdownPreviewApp.swift   DocumentGroup(viewing:) + Find menu
    ├── ContentView.swift          NSTextView (TextKit 1) host, centred column, drop target
    ├── MarkdownRenderer.swift     swift-markdown AST → NSAttributedString (tables, code, images…)
    ├── Document.swift             FileDocument + FileWatcher (live reload)
    └── Sample.md                  element gallery for manual testing
