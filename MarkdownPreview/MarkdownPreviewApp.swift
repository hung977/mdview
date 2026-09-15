import SwiftUI

@main
struct MarkdownPreviewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 800, height: 900)
    }
}
