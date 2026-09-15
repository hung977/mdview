import SwiftUI

@main
struct MDViewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1100, height: 900)
        .windowToolbarStyle(.unified)   // sidebar + glass toolbar, like Preview.app
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Use MDViewer as Default Markdown Viewer") { DefaultHandler.setAsDefault() }
            }
            // SwiftUI's default Edit menu has no Find items; these drive the toolbar search field.
            CommandGroup(after: .pasteboard) {
                Menu("Find") {
                    Button("Find…") { NotificationCenter.default.post(name: .mdviewFocusSearch, object: nil) }
                        .keyboardShortcut("f")
                    Button("Find Next") { ViewerView.inKeyWindow()?.findNext(nil) }.keyboardShortcut("g")
                    Button("Find Previous") { ViewerView.inKeyWindow()?.findPrevious(nil) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                }
            }
            CommandGroup(before: .sidebar) {
                Button("Actual Size") { ViewerView.inKeyWindow()?.actualSize(nil) }.keyboardShortcut("0")
                Button("Zoom In") { ViewerView.inKeyWindow()?.zoomIn(nil) }.keyboardShortcut("+")
                Button("Zoom Out") { ViewerView.inKeyWindow()?.zoomOut(nil) }.keyboardShortcut("-")
                Divider()
            }
        }
    }
}
