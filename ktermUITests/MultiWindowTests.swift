import XCTest

/// Quit hotkey from the app menu. New Window is ⌘⇧N; Cycle Windows is the
/// system ⌘`. Cold `open -a kterm <dir>` still creates the first window via
/// `AppModel.openNewWindow`.
final class MultiWindowTests: KtermUITestCase {
    func testQuitHotkey() {
        XCTAssertEqual(app.state, .runningForeground)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(surface.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .runningForeground)
    }
}
