import SwiftUI

@main
struct MarkdownPreviewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 800, height: 900)
        .commands {
            // SwiftUI's default Edit menu has no Find items; these drive NSTextView's native find bar.
            CommandGroup(after: .pasteboard) {
                Menu("Find") {
                    Button("Find…") { performFind(.showFindInterface) }.keyboardShortcut("f")
                    Button("Find Next") { performFind(.nextMatch) }.keyboardShortcut("g")
                    Button("Find Previous") { performFind(.previousMatch) }.keyboardShortcut("g", modifiers: [.command, .shift])
                }
            }
        }
    }

    private func performFind(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
    }
}
