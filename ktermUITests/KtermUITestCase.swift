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

    /// Waits for the terminal surface to appear, then gives the shell a
    /// moment to attach and print its first prompt before we type into it.
    func waitForShellReady(timeout: TimeInterval = 5) {
        XCTAssertTrue(surface.waitForExistence(timeout: timeout), "terminal surface never appeared")
        Thread.sleep(forTimeInterval: 1.5)
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
}
