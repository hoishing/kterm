import XCTest

/// Clicking a desktop notification focuses the tab that raised it. The real tap
/// is delivered by the system notification UI (not drivable from XCUITest), so
/// this exercises the identical routing through the `kterm://focus-tab?id=<uuid>`
/// URL — the same `AppModel.focusTerminal(withID:)` path the notification tap
/// takes. Each tab exposes its own id to its shell as `KTERM_TAB_ID` (see
/// `SurfaceView`), which is exactly the id a notification carries.
final class NotificationFocusTests: KtermUITestCase {
    func testFocusTabURLRaisesTheIssuingTab() {
        // Tab A is the only vertical tab (group 0), currently selected.
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)

        // In tab A's shell, arm a delayed self-focus via the same URL a
        // notification tap fires, addressing itself by `KTERM_TAB_ID`.
        typeInTerminal("sleep 2 && open \"kterm://focus-tab?id=$KTERM_TAB_ID\"")

        // Move focus to a fresh vertical tab so tab A is no longer selected —
        // this is the "you're looking at a different tab" state in which a
        // notification would have fired.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1, "the new tab should be focused")

        // When the URL fires, focus jumps back to the issuing tab (group 0).
        let rowA = sidebarRows.element(boundBy: 0)
        expectation(for: NSPredicate(format: "value == %@", "selected"), evaluatedWith: rowA)
        waitForExpectations(timeout: 10)
    }
}
