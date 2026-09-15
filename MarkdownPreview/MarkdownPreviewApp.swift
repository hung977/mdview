import SwiftUI

@main
struct MarkdownPreviewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 800, height: 900)
        .commands {
            // SwiftUI's default Edit menu has no Find items; these drive the page's find bar.
            CommandGroup(after: .pasteboard) {
                Menu("Find") {
                    Button("Find…") { send(#selector(ViewerWebView.showFind(_:))) }.keyboardShortcut("f")
                    Button("Find Next") { send(#selector(ViewerWebView.findNext(_:))) }.keyboardShortcut("g")
                    Button("Find Previous") { send(#selector(ViewerWebView.findPrevious(_:))) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                }
            }
        }
    }

    private func send(_ action: Selector) {
        // The web view is not always first responder (e.g. before the first click), so target it directly.
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let webView = window.contentView.flatMap(ViewerWebView.first(in:)) else { return }
        webView.perform(action, with: nil)
    }
}
