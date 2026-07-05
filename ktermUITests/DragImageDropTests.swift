import AppKit
import XCTest

/// End-to-end check that dropping a file onto the terminal inserts its (shell-
/// escaped) path into the live buffer — the behaviour that lets tools like the
/// Claude Code CLI turn a dropped image into `[Image #1]`.
///
/// XCUITest can't reliably synthesize a native Finder file-drag, so the app,
/// when launched with `KTERM_UITEST_DRAG_PATH`, overlays a real AppKit drag
/// source (`UITestDragSource`) vending that file URL. Dragging it onto the
/// surface drives `SurfaceView.performDragOperation` for real.
final class DragImageDropTests: KtermUITestCase {
    /// The file the in-app drag source vends. Kept under `/tmp` with a short,
    /// unique name so the escaped path stays on one terminal line (no soft-wrap
    /// to trip up the substring assertion) and can't collide with stray output.
    private var imagePath = ""

    override func setUpWithError() throws {
        continueAfterFailure = false

        let name = "kterm-e2e-\(UInt32.random(in: 0..<UInt32.max)).png"
        imagePath = "/tmp/\(name)"
        try Self.onePixelPNG.write(to: URL(fileURLWithPath: imagePath))

        app = XCUIApplication()
        app.launchEnvironment["KTERM_UITEST_DRAG_PATH"] = imagePath
        app.launch()
        waitForShellReady()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: imagePath)
        try super.tearDownWithError()
    }

    func testDroppingFileInsertsItsPath() {
        typeInTerminal("clear")

        let source = app.descendants(matching: .any)
            .matching(identifier: "uitest.dragSource").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5), "drag source overlay never appeared")

        // Drag the file onto the terminal. This lands the escaped path on the
        // prompt line via the real drop handler; it is not executed.
        source.press(forDuration: 0.5, thenDragTo: surface)
        Thread.sleep(forTimeInterval: 0.3)

        // Select the top of the screen and copy it, then assert the dropped
        // path is sitting in the buffer.
        let copied = copyOfSelection(
            from: CGVector(dx: 0.01, dy: 0.02), to: CGVector(dx: 0.99, dy: 0.4), until: imagePath)

        XCTAssertTrue(
            copied.contains(imagePath),
            "expected dropped path \(imagePath) in terminal, got: \(copied)"
        )
    }

    /// A minimal valid 1×1 PNG, so the vended file is a real image on disk.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
