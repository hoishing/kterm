import XCTest

/// Single-window tab and sidebar hotkeys wired up in `ktermApp.swift`'s
/// `.commands` block: ⌘T/⌘N create tabs, ⌘W closes them, ⌘B toggles the
/// sidebar, ⌘⇧[]/⌘⌃[] cycle, ⌘<digit> selects by position, and the default
/// `kterm-new-tab-position = after-current` governs where new tabs land.
///
/// These assertions run as one flow per method to amortize the app-launch
/// cost; state accumulates, so counts are asserted as running totals.
final class TabHotkeyTests: KtermUITestCase {
    /// ⌘T (horizontal tab / new terminal in the current group): create+select,
    /// ⌘⇧[] cycling, after-current placement, ⌘W close, and group scoping.
    func testHorizontalTabHotkeys() {
        XCTAssertEqual(tabChips.count, 1)

        // ⌘T creates and selects a new horizontal tab.
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 2)
        XCTAssertEqual(selectedIndex(of: tabChips), 1, "the new terminal should become selected")

        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 3)
        XCTAssertEqual(selectedIndex(of: tabChips), 2)

        // ⌘⇧[ / ⌘⇧] cycle horizontal tabs, wrapping around.
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertEqual(selectedIndex(of: tabChips), 1)
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertEqual(selectedIndex(of: tabChips), 2)
        app.typeKey("]", modifierFlags: [.command, .shift]) // wraps around
        XCTAssertEqual(selectedIndex(of: tabChips), 0)

        // With the default `after-current`, ⌘T from a middle tab inserts right
        // after it (lands at index 2, not the end) instead of appending.
        app.typeKey("]", modifierFlags: [.command, .shift]) // select middle (index 1)
        XCTAssertEqual(selectedIndex(of: tabChips), 1)
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 4)
        XCTAssertEqual(selectedIndex(of: tabChips), 2, "new tab should land right after the current one")

        // ⌘W closes the active tab.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 3)

        // Horizontal tabs are scoped to their vertical tab: a fresh group
        // starts with a single terminal, and switching back restores the
        // original group's tabs.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 1, "a fresh vertical tab starts with a single terminal")
        app.typeKey("[", modifierFlags: [.command, .control]) // back to the first group
        XCTAssertEqual(tabChips.count, 3, "the original group should still have its terminals")
    }

    /// ⌘N (vertical tab / new sidebar group) plus ⌘B sidebar toggle, ⌘<digit>
    /// position select, ⌘⌃[] cycling, after-current placement, and the
    /// closing-the-last-terminal-drops-the-group behaviour.
    func testVerticalTabAndSidebarHotkeys() {
        // ⌘B toggles the sidebar (done first, while state is simple).
        XCTAssertTrue(sidebar.exists)
        app.typeKey("b", modifierFlags: .command)
        XCTAssertFalse(sidebar.exists)
        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(sidebar.exists)

        // ⌘N creates and selects a new vertical tab (sidebar group).
        XCTAssertEqual(sidebarRows.count, 1)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 2)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1, "the new group should become selected")

        app.typeKey("n", modifierFlags: .command) // groups [0,1,2], selected 2
        XCTAssertEqual(sidebarRows.count, 3)

        // ⌘<digit> selects a group by position; out-of-range is a no-op.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)
        app.typeKey("9", modifierFlags: .command) // out of range: no-op
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)

        // ⌘⌃[ / ⌘⌃] cycle vertical tabs, wrapping around.
        app.typeKey("[", modifierFlags: [.command, .control])
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)
        app.typeKey("]", modifierFlags: [.command, .control])
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)
        app.typeKey("]", modifierFlags: [.command, .control]) // wraps around
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)

        // With the default `after-current`, ⌘N from a middle group inserts
        // right after it (lands at index 2, not the end).
        app.typeKey("]", modifierFlags: [.command, .control]) // select middle (index 1)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 4)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2, "new group should land right after the current one")

        // The just-created group (index 2) holds a single terminal, so ⌘W on
        // its last terminal drops the whole group.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 3, "closing a group's last terminal should drop the group")
    }
}
