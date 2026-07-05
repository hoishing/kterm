import XCTest

/// Behaviour around notifications/bells arriving for tabs the user isn't looking
/// at. All of it rides one app launch (state accumulates across the phases):
///
///  1. **Unread dot on a horizontal tab chip** — a bell in a backgrounded
///     terminal marks its `TabChip` unread; selecting the tab clears it.
///  2. **Unread dot on a sidebar row** — a bell in a backgrounded *group* marks
///     that group's `SidebarRow` unread (derived from the unread tab it holds);
///     selecting the group clears it.
///  3. **Notification-tap focus routing** — clicking a desktop notification
///     focuses the issuing tab. The real tap is delivered by the system
///     notification UI (not drivable from XCUITest), so this exercises the
///     identical routing through the `kterm://focus-tab?id=<uuid>` URL — the same
///     `AppModel.focusTerminal(withID:)` path the tap takes. Each tab exposes its
///     id to its shell as `KTERM_TAB_ID` (see `SurfaceView`), the id a
///     notification carries.
///
/// Unread state is asserted via each tab's `.accessibilityValue` ("unread" vs
/// "selected"/"unselected"). The content-area attention flash (`AttentionRing`)
/// is a transient opacity animation with no stable accessibility state, so it is
/// not asserted here — it's covered by the build compiling and by manual check.
///
/// Each `printf '\a'` bell is armed behind `sleep 2` so it fires *after* we've
/// switched away, reproducing the "you're looking at a different tab" state that
/// makes the notification (and thus the highlight) meaningful.
final class NotificationFocusTests: KtermUITestCase {
    func testUnreadHighlightAndFocusRouting() {
        // Tab A is the only tab of the only group (index 0), currently selected.
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)
        XCTAssertEqual(tabChips.count, 1)

        // ── 1. Horizontal-chip unread ──────────────────────────────────────
        // Arm a bell in tab A, then ⌘T to a new horizontal tab B so A goes to
        // the background before the bell fires.
        typeInTerminal("sleep 2 && printf '\\a'")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(tabChips.count, 2)
        XCTAssertEqual(selectedIndex(of: tabChips), 1)

        // The bell fires in the unfocused tab A → its chip shows the unread dot.
        let chipA = tabChips.element(boundBy: 0)
        waitForValue(chipA, toEqual: "unread", timeout: 10)

        // Selecting tab A (⌘⇧[ wraps 1 → 0) clears its unread marker.
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertEqual(selectedIndex(of: tabChips), 0)
        waitForValue(chipA, toEqual: "selected")

        // ── 2. Sidebar-row unread (group-level) ─────────────────────────────
        // Arm another bell in the now-focused tab A, then ⌘N to a fresh group so
        // group 0 goes to the background before the bell fires.
        typeInTerminal("sleep 2 && printf '\\a'")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 2)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)

        // The bell fires in group 0 (not visible) → its row shows the dot,
        // derived from the unread tab A it contains.
        let row0 = sidebarRows.element(boundBy: 0)
        waitForValue(row0, toEqual: "unread", timeout: 10)

        // Selecting group 0 (⌘1) clears it.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)
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
    }
}
