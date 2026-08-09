import XCTest

/// Quit hotkey from the app menu. Multi-window open/cycle hotkeys were removed
/// (no New Window / Cycle Windows); cold `open -a kterm <dir>` still creates the
/// first window via `AppModel.openNewWindow` without a user-facing shortcut.
final class MultiWindowTests: KtermUITestCase {
    func testQuitHotkey() {
        XCTAssertEqual(app.state, .runningForeground)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(surface.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .runningForeground)
    }
}
