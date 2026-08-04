import XCTest

/// Single-window tab and sidebar hotkeys wired up in `ktermApp.swift`'s
/// `.commands` block: ⌘T creates tabs, ⌘W closes them, ⌘B toggles the
/// sidebar, ⌘⇧[] cycles, ⌘<digit> selects by position, and the default
/// `kterm-new-tab-position = after-current` governs where new tabs land.
///
/// These assertions run as one flow to amortize the app-launch cost; state
/// accumulates, so counts are asserted as running totals.
final class TabHotkeyTests: KtermUITestCase {
    func testTabAndSidebarHotkeys() {
        // ⌘B toggles the sidebar (done first, while state is simple).
        XCTAssertTrue(sidebar.exists)
        app.typeKey("b", modifierFlags: .command)
        XCTAssertFalse(sidebar.exists)
        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(sidebar.exists)

        // ⌘T creates and selects a new tab.
        XCTAssertEqual(sidebarRows.count, 1)
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 2)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1, "the new tab should become selected")

        app.typeKey("t", modifierFlags: .command) // tabs [0,1,2], selected 2
        XCTAssertEqual(sidebarRows.count, 3)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)

        // ⌘<digit> selects a tab by position; out-of-range is a no-op.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)
        app.typeKey("9", modifierFlags: .command) // out of range: no-op
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)

        // ⌘⇧[ / ⌘⇧] cycle tabs, wrapping around.
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)
        app.typeKey("]", modifierFlags: [.command, .shift]) // wraps around
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)

        // With the default `after-current`, ⌘T from a middle tab inserts right
        // after it (lands at index 2, not the end).
        app.typeKey("]", modifierFlags: [.command, .shift]) // select middle (index 1)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 4)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2, "new tab should land right after the current one")

        // ⌘W closes the active tab.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 3)
    }
}
