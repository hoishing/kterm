import XCTest

/// Behaviour around notifications/bells arriving for tabs the user isn't looking
/// at. All of it rides one app launch (state accumulates across the phases):
///
///  1. **🔔 on a horizontal tab chip** — a bell in a backgrounded terminal marks
///     its `TabChip` with a 🔔 (ghostty-style). Selecting the tab does NOT clear
///     it; only interacting with the content area (a keystroke or click) does.
///  2. **Unread dot on a sidebar row** — a bell in a backgrounded *group* marks
///     that group's `SidebarRow` with a dot (derived from the unread tab it
///     holds). Selecting the group does NOT clear it; interacting with the
///     content area does.
///  3. **Notification-tap focus routing** — clicking a desktop notification
///     focuses the issuing tab. The real tap is delivered by the system
///     notification UI (not drivable from XCUITest), so this exercises the
///     identical routing through the `kterm://focus-tab?id=<uuid>` URL — the same
///     `AppModel.focusTerminal(withID:)` path the tap takes. Each tab exposes its
///     id to its shell as `KTERM_TAB_ID` (see `SurfaceView`), the id a
///     notification carries.
///  4. **Content-area attention border** — a notification for the *visible*,
///     frontmost tab (a build finishing while you watch its output) leaves no
///     unread marker but draws a static border around the content area. The
///     border and any unread marker share one dismiss trigger: interacting with
///     the content area.
///
/// Unread state is asserted via each tab's `.accessibilityValue`, where "unread"
/// takes precedence over "selected"/"unselected" (a tab stays unread even while
/// selected, until interacted with). The attention border is asserted via the
/// `terminal.surface` element's `.accessibilityValue` ("attention" vs "idle"),
/// which `SurfaceContainer` mirrors from `Terminal.showAttention`.
///
/// Each `printf '\a'` bell is armed behind `sleep 2` so it fires *after* we've
/// switched away, reproducing the "you're looking at a different tab" state that
/// makes the notification (and thus the marker) meaningful.
final class NotificationFocusTests: KtermUITestCase {
    func testUnreadHighlightAndFocusRouting() {
        // Tab A is the only tab of the only group (index 0), currently selected.
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)
        XCTAssertEqual(tabChips.count, 1)

        // ── 1. Horizontal-chip 🔔, dismissed by interaction ─────────────────
        // Arm a bell in tab A, then ⌘T to a new horizontal tab B so A goes to
        // the background before the bell fires.
        typeInTerminal("sleep 2 && printf '\\a'")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 2)
        XCTAssertEqual(selectedIndex(of: tabChips), 1)

        // The bell fires in the unfocused tab A → its chip shows the 🔔.
        let chipA = tabChips.element(boundBy: 0)
        let chipB = tabChips.element(boundBy: 1)
        waitForValue(chipA, toEqual: "unread", timeout: 10)

        // Selecting tab A (⌘⇧[ wraps 1 → 0) does NOT clear it: focus alone no
        // longer acknowledges the notification.
        app.typeKey("[", modifierFlags: [.command, .shift])
        waitForValue(chipB, toEqual: "unselected")
        XCTAssertEqual(chipA.value as? String, "unread",
                       "selecting the tab must not clear its 🔔")

        // Interacting with the content area (a click) clears it.
        surface.click()
        waitForValue(chipA, toEqual: "selected")

        // ── 2. Sidebar-row dot, dismissed by interaction ────────────────────
        // Arm another bell in the now-focused tab A, then ⌘N to a fresh group so
        // group 0 goes to the background before the bell fires.
        typeInTerminal("sleep 2 && printf '\\a'")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 2)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)

        // The bell fires in group 0 (not visible) → its row shows the dot,
        // derived from the unread tab A it contains.
        let row0 = sidebarRows.element(boundBy: 0)
        let row1 = sidebarRows.element(boundBy: 1)
        waitForValue(row0, toEqual: "unread", timeout: 10)

        // Selecting group 0 (⌘1) does NOT clear it.
        app.typeKey("1", modifierFlags: .command)
        waitForValue(row1, toEqual: "unselected")
        XCTAssertEqual(row0.value as? String, "unread",
                       "selecting the group must not clear its dot")

        // Interacting with group 0's content area clears it.
        surface.click()
        waitForValue(row0, toEqual: "selected")

        // ── 3. Notification-tap focus routing ───────────────────────────────
        // In tab A's shell, arm a delayed self-focus via the same URL a
        // notification tap fires, addressing itself by `KTERM_TAB_ID`.
        typeInTerminal("sleep 2 && open \"kterm://focus-tab?id=$KTERM_TAB_ID\"")

        // Move focus to the other group so tab A is no longer selected.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1, "the other group should be focused")

        // When the URL fires, focus jumps back to the issuing tab (group 0).
        waitForValue(row0, toEqual: "selected", timeout: 10)

        // ── 4. Content-area attention border ────────────────────────────────
        // Focus is back on the visible tab A. Arm a bell there but DON'T switch
        // away, so the notification lands on the tab the user is looking at.
        XCTAssertEqual(surface.value as? String, "idle", "border starts clear")
        typeInTerminal("sleep 2 && printf '\\a'")

        // Bell fires in the visible, frontmost tab → no unread marker (nothing
        // to catch up on), just the static attention border. Don't touch the
        // surface until we've seen it, or the interaction would clear it early.
        waitForValue(surface, toEqual: "attention", timeout: 10)
        XCTAssertEqual(row0.value as? String, "selected",
                       "a notification for the visible tab leaves no unread marker")

        // Interacting with the content area (a click) dismisses the border.
        surface.click()
        waitForValue(surface, toEqual: "idle")
    }
}
