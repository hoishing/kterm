import XCTest

/// Tab titles track libghostty's surface title (OSC 2), the same source as
/// Ghostty's tab bar. At the prompt, shell-integration `title` sets that to
/// an abbreviated cwd: `~` for home, `~/...` inside home, full path outside
/// (see `Terminal.displayTitle` in AppModel.swift). While a command is
/// running the title becomes the command text; these assertions cover the
/// idle/cwd form.
///
/// Both views truncate long titles from the front (`.truncationMode(.head)`)
/// so the trailing folder always stays visible, but that's a rendering-only
/// concern — accessibility labels always expose the full, untruncated
/// string, so it isn't asserted here. It was verified manually by screenshot
/// (a narrow sidebar row showing "...oj/kterm/Sources/UI").
final class TabTitleTests: KtermUITestCase {
    func testTitlesTrackWorkingDirectory() {
        // A fresh terminal starts at home.
        XCTAssertEqual(sidebarRows.element(boundBy: 0).label, "~", "a fresh terminal starts at home")

        // A path inside home shows as `~/…`; a path outside home shows in full.
        typeInTerminal("cd ~/Library")
        waitForLabel(sidebarRows.element(boundBy: 0), toEqual: "~/Library")
        typeInTerminal("cd /Applications")
        waitForLabel(sidebarRows.element(boundBy: 0), toEqual: "/Applications")

        // Return home so the tab we're about to open — which inherits the
        // current tab's cwd — also starts at home.
        typeInTerminal("cd ~")
        waitForLabel(sidebarRows.element(boundBy: 0), toEqual: "~")

        // Each horizontal tab tracks its own directory independently.
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(tabChips.element(boundBy: 0).label, "~")
        // The new terminal's pwd report arrives asynchronously (OSC 7), so it
        // briefly reads "Terminal" (the no-pwd fallback) before settling on "~".
        waitForLabel(tabChips.element(boundBy: 1), toEqual: "~")

        typeInTerminal("cd ~/Library")
        waitForLabel(tabChips.element(boundBy: 1), toEqual: "~/Library")
        XCTAssertEqual(tabChips.element(boundBy: 0).label, "~", "the other tab's directory is untouched")
    }
}
