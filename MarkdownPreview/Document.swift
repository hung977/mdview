import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (UTImportedTypeDeclarations); there is no system constant for Markdown.
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown")
}

/// Read-only document: the bytes are read once by DocumentGroup; live updates come from FileWatcher.
struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownDocument]

    var text: String

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = Self.decode(data)
    }

    /// Never called in viewing mode; required by the protocol.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }

    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
