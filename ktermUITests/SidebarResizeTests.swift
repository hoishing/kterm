import XCTest

/// `SidebarResizeHandle` in RootView.swift: a thin AppKit drag strip that
/// resizes the sidebar between 120 and 480pt.
final class SidebarResizeTests: KtermUITestCase {
    private var handle: XCUIElement { app.buttons["sidebar.resizeHandle"] }

    func testHandleResizesAndClamps() {
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let initialWidth = sidebar.frame.width

        // Dragging the handle right widens the sidebar.
        dragHandle(dx: 80)
        XCTAssertGreaterThan(sidebar.frame.width, initialWidth + 40,
                              "dragging the handle right should widen the sidebar")

        // Dragging it back left narrows it again.
        let widenedWidth = sidebar.frame.width
        dragHandle(dx: -60)
        XCTAssertLessThan(sidebar.frame.width, widenedWidth - 30,
                           "dragging the handle left should narrow the sidebar")

        // Extreme drags clamp to the configured 120–480pt range.
        dragHandle(dx: 1000)
        XCTAssertLessThanOrEqual(sidebar.frame.width, 480, "sidebar width should clamp to its maximum")
        dragHandle(dx: -1000)
        XCTAssertGreaterThanOrEqual(sidebar.frame.width, 120, "sidebar width should clamp to its minimum")
    }

    /// Grab the handle at its center and drag it `dx` points horizontally.
    private func dragHandle(dx: CGFloat) {
        let center = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: dx, dy: 0)))
    }
}
