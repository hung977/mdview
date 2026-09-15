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

/// Watches one file for changes with a DispatchSource. Editors that save atomically replace the
/// inode (rename/delete), so the watcher re-arms on the path after such events.
final class FileWatcher {
    private let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        path = url.path
        self.onChange = onChange
        arm(attempt: 0)
    }

    deinit {
        source?.cancel()
        pending?.cancel()
    }

    private func arm(attempt: Int) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            guard attempt < 10 else { return }   // file gone for good
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.arm(attempt: attempt + 1) }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                source.cancel()
                self.source = nil
                self.arm(attempt: 0)
            }
            self.scheduleChange()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    /// Coalesces bursts of events (editors often write several times per save).
    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}

/// Makes MDViewer the default app for Markdown files (what Finder, Quick Look's "Open with" and
/// double-click use). Offered once on first launch and available from the app menu afterwards.
enum DefaultHandler {
    private static let offeredKey = "didOfferDefaultHandler"

    static var isDefault: Bool {
        let sample = URL(fileURLWithPath: "/tmp/mdview-probe.md")
        return NSWorkspace.shared.urlForApplication(toOpen: sample)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// True the first time the app runs while another app owns Markdown files; marks the offer as made.
    static func shouldOffer() -> Bool {
        guard !UserDefaults.standard.bool(forKey: offeredKey), !isDefault else { return false }
        UserDefaults.standard.set(true, forKey: offeredKey)
        return true
    }

    static func offer() {
        let alert = NSAlert()
        alert.messageText = "Open Markdown files with MDViewer?"
        alert.informativeText = "Finder, Quick Look and double-click will use MDViewer for .md and .markdown files. You can change this later from the MDViewer menu."
        alert.addButton(withTitle: "Use MDViewer")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { setAsDefault() }
    }

    static func setAsDefault() {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .markdownDocument) { error in
            guard let error else { return }
            DispatchQueue.main.async { NSAlert(error: error).runModal() }
        }
    }
}
