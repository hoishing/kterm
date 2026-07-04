import XCTest

/// ⌘N (vertical tab / new sidebar group) and ⌘T (horizontal tab / new
/// terminal in the current group).
final class TabCreationTests: KtermUITestCase {
    func testCommandNCreatesAndSelectsAVerticalTab() {
        XCTAssertEqual(sidebarRows.count, 1)

        app.typeKey("n", modifierFlags: .command)

        XCTAssertEqual(sidebarRows.count, 2)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1, "the new group should become selected")
    }

    func testCommandTCreatesAndSelectsAHorizontalTab() {
        XCTAssertEqual(tabChips.count, 1)

        app.typeKey("t", modifierFlags: .command)

        XCTAssertEqual(tabChips.count, 2)
        XCTAssertEqual(selectedIndex(of: tabChips), 1, "the new terminal should become selected")
    }

    // With the default `kterm-new-tab-position = after-current`, ⌘T from a
    // middle tab inserts right after it (selected there) instead of appending.
    // Selecting index 2 (not the last index 3) proves it's "after-current",
    // not "end". CI runners have no config file, so the default applies.
    func testCommandTOpensNewTabRightAfterCurrent() {
        app.typeKey("t", modifierFlags: .command) // tabs [0,1], selected 1
        app.typeKey("t", modifierFlags: .command) // tabs [0,1,2], selected 2
        app.typeKey("[", modifierFlags: [.command, .shift]) // select 1 (middle)
        XCTAssertEqual(selectedIndex(of: tabChips), 1)

        app.typeKey("t", modifierFlags: .command)

        XCTAssertEqual(tabChips.count, 4)
        XCTAssertEqual(selectedIndex(of: tabChips), 2, "new tab should land right after the current one")
    }

    // Same default, but for ⌘N vertical tabs (sidebar groups).
    func testCommandNOpensNewTabRightAfterCurrent() {
        app.typeKey("n", modifierFlags: .command) // groups [0,1], selected 1
        app.typeKey("n", modifierFlags: .command) // groups [0,1,2], selected 2
        app.typeKey("[", modifierFlags: [.command, .control]) // select 1 (middle)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)

        app.typeKey("n", modifierFlags: .command)

        XCTAssertEqual(sidebarRows.count, 4)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2, "new group should land right after the current one")
    }

    func testHorizontalTabsAreScopedToTheirVerticalTab() {
        app.typeKey("t", modifierFlags: .command) // 2 terminals in group 1
        app.typeKey("n", modifierFlags: .command) // group 2, back to 1 terminal
        XCTAssertEqual(sidebarRows.count, 2)
        XCTAssertEqual(tabChips.count, 1, "a fresh vertical tab starts with a single terminal")

        app.typeKey("[", modifierFlags: [.command, .control]) // back to group 1
        XCTAssertEqual(tabChips.count, 2, "group 1 should still have both its terminals")
    }

    func testClosingAGroupsLastTerminalDropsTheGroup() {
        app.typeKey("n", modifierFlags: .command) // second, empty-ish group
        XCTAssertEqual(sidebarRows.count, 2)

        app.typeKey("w", modifierFlags: .command) // close its only terminal

        XCTAssertEqual(sidebarRows.count, 1, "closing a group's last terminal should drop the group")
    }
}
