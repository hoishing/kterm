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

    func testCommandControlBracketsCycleVerticalTabs() {
        app.typeKey("n", modifierFlags: .command) // group 2
        app.typeKey("n", modifierFlags: .command) // group 3
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)

        app.typeKey("[", modifierFlags: [.command, .control])
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)

        app.typeKey("]", modifierFlags: [.command, .control])
        XCTAssertEqual(selectedIndex(of: sidebarRows), 2)

        app.typeKey("]", modifierFlags: [.command, .control]) // wraps around
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)
    }

    func testCommandShiftNOpensANewWindow() {
        let initial = app.windows.count
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForWindowCount(initial + 1), "⌘⇧N should open a new window")
    }

    func testCommandBacktickCyclesBetweenWindows() {
        let initial = app.windows.count

        // Give the launch window (A) a distinctive working directory so it can
        // be told apart from the second window later.
        typeInTerminal("cd /usr")
        waitForLabel(sidebarRows.element(boundBy: 0), toEqual: "/usr")

        // ⌘⇧N opens a second window (B), which becomes key and starts at home.
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForWindowCount(initial + 1), "⌘⇧N should open a second window")
        XCTAssertNotNil(window(withSidebarLabel: "~"), "the new window starts at home")

        // ⌘` cycles key focus off B and back to A. A subsequent ⌘T (which acts
        // on the front window) then adds a tab to A — proving focus switched.
        // If ⌘` were a no-op, ⌘T would instead land in B.
        app.typeKey("`", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5) // let the key-window change propagate
        app.typeKey("t", modifierFlags: .command)

        XCTAssertTrue(
            waitForTabChipCount(2, inWindowWithSidebarLabel: "/usr"),
            "⌘T after ⌘` should add a tab to window A, the cycled-to window")
        XCTAssertEqual(
            window(withSidebarLabel: "~")?.buttons.matching(identifier: "tabstrip.tab").count, 1,
            "the other window should be left untouched")
    }

    func testCommandQQuitsTheApp() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(surface.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .runningForeground)
    }
}
