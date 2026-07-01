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
