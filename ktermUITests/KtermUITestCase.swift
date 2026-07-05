import AppKit
import XCTest

/// Shared launch/teardown and terminal-interaction helpers for kterm's UI
/// tests. Each test gets a fresh `XCUIApplication` (a fresh shell session),
/// so tests never depend on state left behind by another test.
class KtermUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        waitForShellReady()
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground { app.terminate() }
    }

    // SwiftUI maps `.accessibilityElement(children: .contain)` containers to
    // an AXGroup, which XCUITest surfaces as `.group`, not `.other` — query
    // by identifier across any element type so the mapped role doesn't matter.
    var sidebar: XCUIElement { app.descendants(matching: .any).matching(identifier: "sidebar").firstMatch }
    var surface: XCUIElement { app.otherElements["terminal.surface"] }
    var sidebarRows: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.row") }
    var tabChips: XCUIElementQuery { app.buttons.matching(identifier: "tabstrip.tab") }

    /// Waits for the terminal surface to appear, then for its first OSC 7 pwd
    /// report (`~`) to land, so callers never type into a shell that hasn't
    /// actually attached yet. A fixed sleep here isn't reliable: a cold CI
    /// runner can take longer than a local machine to fork/attach the shell,
    /// and keystrokes sent before that happens get lost.
    func waitForShellReady(timeout: TimeInterval = 10) {
        XCTAssertTrue(surface.waitForExistence(timeout: timeout), "terminal surface never appeared")
        waitForLabel(sidebarRows.element(boundBy: 0), toEqual: "~", timeout: timeout)
    }

    /// Clicks the focused terminal to make sure it's first responder, then
    /// types `text`, pressing Return afterwards unless told not to.
    func typeInTerminal(_ text: String, pressReturn: Bool = true) {
        surface.click()
        surface.typeText(text)
        if pressReturn {
            surface.typeText("\r")
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// The index of the element in `query` whose accessibility value marks
    /// it "selected" (see `SidebarRow`/`TabChip`'s `.accessibilityValue`).
    func selectedIndex(of query: XCUIElementQuery) -> Int? {
        for i in 0..<query.count where query.element(boundBy: i).value as? String == "selected" {
            return i
        }
        return nil
    }

    /// Waits until `element`'s accessibility label equals `expected`.
    func waitForLabel(_ element: XCUIElement, toEqual expected: String, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "label == %@", expected)
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    /// Drag-selects a rectangle of the terminal surface (normalized offsets),
    /// ⌘C-copies it, and polls the system pasteboard until it contains `until`
    /// (or times out), returning whatever ended up there. libghostty owns
    /// selection and clipboard writes internally, so tests assert on the real
    /// pasteboard rather than any SwiftUI/accessibility state.
    func copyOfSelection(from: CGVector, to: CGVector, until: String,
                         timeout: TimeInterval = 5) -> String {
        NSPasteboard.general.clearContents()
        let start = surface.coordinate(withNormalizedOffset: from)
        let end = surface.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.1, thenDragTo: end)
        app.typeKey("c", modifierFlags: .command)

        let deadline = Date().addingTimeInterval(timeout)
        var copied = ""
        while Date() < deadline {
            copied = NSPasteboard.general.string(forType: .string) ?? ""
            if copied.contains(until) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return copied
    }

    // MARK: - Multi-window helpers

    /// Polls until the app has exactly `count` windows (or times out).
    func waitForWindowCount(_ count: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.windows.count == count { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return app.windows.count == count
    }

    /// The window whose (only) sidebar row shows `label`, letting tests tell
    /// windows apart by the working directory typed into each.
    func window(withSidebarLabel label: String) -> XCUIElement? {
        for i in 0..<app.windows.count {
            let w = app.windows.element(boundBy: i)
            let row = w.buttons.matching(identifier: "sidebar.row").element(boundBy: 0)
            if row.exists, row.label == label { return w }
        }
        return nil
    }

    /// Polls until the window identified by `label` holds `count` horizontal
    /// tab chips (or times out).
    func waitForTabChipCount(_ count: Int, inWindowWithSidebarLabel label: String,
                             timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let w = window(withSidebarLabel: label),
               w.buttons.matching(identifier: "tabstrip.tab").count == count { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }
}
