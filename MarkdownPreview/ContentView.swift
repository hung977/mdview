import SwiftUI

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?

    var body: some View {
        Text(document.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
