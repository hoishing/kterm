import XCTest

/// Multi-window hotkeys from `ktermApp.swift`'s `.commands` block: ⌘⇧N opens a
/// new window and ⌘` cycles key focus between windows. ⌘Q (quit) runs last,
/// since it tears down the shared app instance.
final class MultiWindowTests: KtermUITestCase {
    func testMultiWindowHotkeysAndQuit() {
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

        // ⌘Q quits the whole app — run last, as it tears down the instance.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(surface.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .runningForeground)
    }
}
