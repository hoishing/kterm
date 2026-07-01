import XCTest

/// Every hotkey wired up in `ktermApp.swift`'s `.commands` block.
final class HotkeyTests: KtermUITestCase {
    func testCommandNCreatesAndSelectsVerticalTab() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 2)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)
    }

    func testCommandTCreatesAndSelectsHorizontalTab() {
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 2)
        XCTAssertEqual(selectedIndex(of: tabChips), 1)
    }

    func testCommandWClosesTheActiveTab() {
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 2)

        app.typeKey("w", modifierFlags: .command)

        XCTAssertEqual(tabChips.count, 1)
    }

    func testCommandBTogglesTheSidebar() {
        XCTAssertTrue(sidebar.exists)

        app.typeKey("b", modifierFlags: .command)
        XCTAssertFalse(sidebar.exists)

        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(sidebar.exists)
    }

    func testCommandDigitSelectsVerticalTabByPosition() {
        app.typeKey("n", modifierFlags: .command) // tab 2
        app.typeKey("n", modifierFlags: .command) // tab 3
        XCTAssertEqual(sidebarRows.count, 3)

        app.typeKey("1", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)

        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)

        app.typeKey("9", modifierFlags: .command) // out of range: no-op
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)
    }

    func testCommandShiftBracketsCycleHorizontalTabs() {
        app.typeKey("t", modifierFlags: .command) // tab 2
        app.typeKey("t", modifierFlags: .command) // tab 3
        XCTAssertEqual(selectedIndex(of: tabChips), 2)

        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertEqual(selectedIndex(of: tabChips), 1)

        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertEqual(selectedIndex(of: tabChips), 2)

        app.typeKey("]", modifierFlags: [.command, .shift]) // wraps around
        XCTAssertEqual(selectedIndex(of: tabChips), 0)
    }

    func testControlShiftBracketsCycleVerticalTabs() {
        app.typeKey("n", modifierFlags: .command) // group 2
        app.typeKey("n", modifierFlags: .command) // group 3
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)

        app.typeKey("[", modifierFlags: [.control, .shift])
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)

        app.typeKey("]", modifierFlags: [.control, .shift])
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)

        app.typeKey("]", modifierFlags: [.control, .shift]) // wraps around
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)
    }

    func testCommandQQuitsTheApp() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(surface.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .runningForeground)
    }
}
