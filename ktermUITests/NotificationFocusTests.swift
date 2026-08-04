import XCTest

/// Behaviour around notifications/bells arriving for tabs the user isn't looking
/// at. All of it rides one app launch (state accumulates across the phases). The
/// set/dismiss rules mirror cmux:
///
///  1. **Unread dot on a sidebar row** — a bell in a backgrounded tab marks
///     that tab's `SidebarRow` with a dot. **Selecting the tab clears it**
///     (cmux marks a notification read on selection).
///  2. **Notification-tap focus routing** — clicking a desktop notification
///     focuses the issuing tab. The real tap is delivered by the system
///     notification UI (not drivable from XCUITest), so this exercises the
///     identical routing through the `kterm://focus-tab?id=<uuid>` URL — the same
///     `AppModel.focusTerminal(withID:)` path the tap takes, which selects (and
///     thereby acknowledges) the tab. Each tab exposes its id to its shell as
///     `KTERM_TAB_ID` (see `SurfaceView`), the id a notification carries.
///  3. **Content-area attention border** — a notification for the *visible*,
///     frontmost tab (a build finishing while you watch its output) draws a
///     static border around the content area *and* leaves an unread marker on
///     the tab (cmux records unread even while focused). Interacting with the
///     content area acknowledges both together.
///  4. **Dock bounce + return-to-foreground dismiss** — a notification arriving
///     while kterm is not the active app bounces the dock icon (ghostty's
///     `requestUserAttention` path) and leaves the marker/border set; bringing
///     kterm back to the foreground acknowledges the selected tab (cmux marks it
///     read on `didBecomeActive`). The bounce has no accessibility surface, so
///     it's observed via the `app.dockBounces` probe
///     (`AppModel.dockAttentionRequests`); it must stay 0 while kterm is
///     frontmost and tick up once a ping lands while hidden.
///
/// Unread state is asserted via each tab's `.accessibilityValue`, where "unread"
/// takes precedence over "selected"/"unselected" (a tab stays unread even while
/// selected, until acknowledged). The attention border is asserted via the
/// `terminal.surface` element's `.accessibilityValue` ("attention" vs "idle"),
/// which `SurfaceContainer` mirrors from `Terminal.showAttention`.
///
/// Each `printf '\a'` bell is armed behind `sleep 2` so it fires *after* we've
/// switched away, reproducing the "you're looking at a different tab" state that
/// makes the notification (and thus the marker) meaningful.
final class NotificationFocusTests: KtermUITestCase {
    func testUnreadHighlightAndFocusRouting() {
        // Tab A is the only tab (index 0), currently selected.
        XCTAssertEqual(selectedIndex(of: sidebarRows), 0)
        XCTAssertEqual(sidebarRows.count, 1)

        // ── 1. Sidebar-row dot, dismissed by selecting the tab ───────────────
        // Arm a bell in tab A, then ⌘T to a new tab B so A goes to the
        // background before the bell fires.
        typeInTerminal("sleep 2 && printf '\\a'")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(sidebarRows.count, 2)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1)

        // The bell fires in the unfocused tab A → its row shows the dot.
        let rowA = sidebarRows.element(boundBy: 0)
        let rowB = sidebarRows.element(boundBy: 1)
        waitForValue(rowA, toEqual: "unread", timeout: 10)

        // Selecting tab A (⌘⇧[ wraps 1 → 0) acknowledges it: the dot clears.
        app.typeKey("[", modifierFlags: [.command, .shift])
        waitForValue(rowA, toEqual: "selected")
        XCTAssertEqual(rowB.value as? String, "unselected")

        // ── 2. Notification-tap focus routing ───────────────────────────────
        // In tab A's shell, arm a delayed self-focus via the same URL a
        // notification tap fires, addressing itself by `KTERM_TAB_ID`.
        typeInTerminal("sleep 2 && open \"kterm://focus-tab?id=$KTERM_TAB_ID\"")

        // Move focus to the other tab so tab A is no longer selected.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(selectedIndex(of: sidebarRows), 1, "the other tab should be focused")

        // When the URL fires, focus jumps back to the issuing tab (tab A).
        waitForValue(rowA, toEqual: "selected", timeout: 10)

        // ── 3. Content-area attention border + unread on the visible tab ─────
        // Focus is back on the visible tab A. Arm a bell there but DON'T switch
        // away, so the notification lands on the tab the user is looking at.
        XCTAssertEqual(surface.value as? String, "idle", "border starts clear")
        typeInTerminal("sleep 2 && printf '\\a'")

        // Bell fires in the visible, frontmost tab → the static attention border
        // AND an unread marker on its row (cmux records unread even while
        // focused). Don't touch the surface until we've seen it, or the
        // interaction would acknowledge it early.
        waitForValue(surface, toEqual: "attention", timeout: 10)
        XCTAssertEqual(rowA.value as? String, "unread",
                       "a notification for the visible tab also marks it unread")

        // Interacting with the content area (a click) acknowledges both.
        surface.click()
        waitForValue(surface, toEqual: "idle")
        waitForValue(rowA, toEqual: "selected")

        // ── 4. Dock bounce + return-to-foreground dismiss ───────────────────
        // Every ping so far arrived while kterm was frontmost, so none bounced.
        let dockBounces = app.otherElements["app.dockBounces"]
        XCTAssertEqual(dockBounces.value as? String, "0",
                       "pings while kterm is frontmost must not bounce the dock")

        // Arm a bell, then hide kterm (⌘H resigns active) before it fires so the
        // ping lands while kterm is not the active app.
        typeInTerminal("sleep 2 && printf '\\a'")
        app.typeKey("h", modifierFlags: .command)
        // Let the bell fire while hidden (armed behind `sleep 2`); don't
        // reactivate first, or kterm would be active again when it fires.
        Thread.sleep(forTimeInterval: 3)

        // Bring kterm back: the ping bounced the dock exactly once, and
        // returning to the foreground acknowledges the selected tab, clearing
        // the border and unread marker it left behind.
        app.activate()
        waitForValue(dockBounces, toEqual: "1", timeout: 10)
        waitForValue(surface, toEqual: "idle")
        waitForValue(rowA, toEqual: "selected")
    }
}
