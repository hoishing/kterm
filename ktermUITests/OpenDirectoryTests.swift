import AppKit
import XCTest

/// End-to-end check that `open -a kterm <dir>` on an already-running kterm opens
/// the folder as a new tab in the current window — instead of spawning a second
/// window. SwiftUI's `WindowGroup` auto-opens a window for a document-open, so
/// the app declines external opens (`.handlesExternalEvents(matching:)`) and
/// routes the folder into the front window itself; this guards that wiring.
final class OpenDirectoryTests: KtermUITestCase {
    private var folderURL: URL!
    private var expectedLabel = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A uniquely-named folder under home, so its sidebar label is a stable
        // `~/…` path we can wait on (home isn't sandboxed away here).
        let name = "kterm-e2e-\(UInt32.random(in: 0..<UInt32.max))"
        folderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        expectedLabel = "~/\(name)"
    }

    override func tearDownWithError() throws {
        if let folderURL { try? FileManager.default.removeItem(at: folderURL) }
        try super.tearDownWithError()
    }

    func testOpenFolderReusesCurrentWindow() throws {
        // The launch window starts as one window with one group (at home).
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(sidebarRows.count, 1)

        try openFolder(folderURL)

        // The folder lands as a new vertical tab whose shell started in it — so
        // its sidebar row shows the folder path. Waiting on that proves the open
        // was processed; a cold CI runner needs a generous timeout to attach.
        waitForLabel(sidebarRows.element(boundBy: 1), toEqual: expectedLabel, timeout: 15)

        // The crux: it reused the existing window rather than spawning a surplus.
        XCTAssertTrue(
            waitForWindowCount(1),
            "`open -a kterm <dir>` must reuse the current window, not open a new one")
        XCTAssertEqual(sidebarRows.count, 2, "the folder should add exactly one vertical tab")
    }

    /// Runs `open -a <running kterm bundle> <dir>`, delivering a folder-open to
    /// the already-running instance exactly as `open -a kterm <dir>` does — but
    /// targeting the exact bundle under test so LaunchServices can't resolve the
    /// name to some other installed kterm.
    private func openFolder(_ url: URL) throws {
        let bundleURL = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.kterm.app")
                .first?.bundleURL,
            "no running kterm instance to target")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", bundleURL.path, url.path]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0, "`open -a kterm <dir>` exited non-zero")
    }
}
