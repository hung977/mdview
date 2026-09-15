import XCTest
@testable import MarkdownPreview

final class FileWatcherTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("doc.md")
        try "one".write(to: url, atomically: false, encoding: .utf8)
    }

    func testInPlaceWriteFiresOnce() throws {
        let fired = expectation(description: "change")
        let watcher = FileWatcher(url: url) { fired.fulfill() }
        try "two".write(to: url, atomically: false, encoding: .utf8)
        wait(for: [fired], timeout: 2)
        withExtendedLifetime(watcher) {}
    }

    func testAtomicReplaceFiresAndKeepsWatching() throws {
        let first = expectation(description: "first"), second = expectation(description: "second")
        var count = 0
        let watcher = FileWatcher(url: url) {
            count += 1
            if count == 1 { first.fulfill() } else if count == 2 { second.fulfill() }
        }
        try "two".write(to: url, atomically: true, encoding: .utf8)     // rename over the watched inode
        wait(for: [first], timeout: 2)
        try "three".write(to: url, atomically: true, encoding: .utf8)
        wait(for: [second], timeout: 2)
        withExtendedLifetime(watcher) {}
    }

    func testDeallocatedWatcherStopsFiring() throws {
        var fired = false
        var watcher: FileWatcher? = FileWatcher(url: url) { fired = true }
        watcher = nil
        try "two".write(to: url, atomically: false, encoding: .utf8)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(fired)
        XCTAssertNil(watcher)
    }
}
