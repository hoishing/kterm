import XCTest

/// `SidebarResizeHandle` in RootView.swift: a thin AppKit drag strip that
/// resizes the sidebar between 120 and 480pt.
final class SidebarResizeTests: KtermUITestCase {
    private var handle: XCUIElement { app.buttons["sidebar.resizeHandle"] }

    func testDraggingTheHandleWidensTheSidebar() {
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let initialWidth = sidebar.frame.width

        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 80, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertGreaterThan(sidebar.frame.width, initialWidth + 40,
                              "dragging the handle right should widen the sidebar")
    }

    func testDraggingTheHandleLeftNarrowsTheSidebar() {
        XCTAssertTrue(handle.waitForExistence(timeout: 5))

        // Widen first so there's room to narrow it back.
        let widen = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        widen.press(forDuration: 0.1, thenDragTo: widen.withOffset(CGVector(dx: 100, dy: 0)))
        let widenedWidth = sidebar.frame.width

        let narrow = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        narrow.press(forDuration: 0.1, thenDragTo: narrow.withOffset(CGVector(dx: -60, dy: 0)))

        XCTAssertLessThan(sidebar.frame.width, widenedWidth - 30,
                           "dragging the handle left should narrow the sidebar")
    }

    func testSidebarWidthClampsToItsConfiguredRange() {
        XCTAssertTrue(handle.waitForExistence(timeout: 5))

        let maxDrag = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        maxDrag.press(forDuration: 0.1, thenDragTo: maxDrag.withOffset(CGVector(dx: 1000, dy: 0)))
        XCTAssertLessThanOrEqual(sidebar.frame.width, 480, "sidebar width should clamp to its maximum")

        let minDrag = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        minDrag.press(forDuration: 0.1, thenDragTo: minDrag.withOffset(CGVector(dx: -1000, dy: 0)))
        XCTAssertGreaterThanOrEqual(sidebar.frame.width, 120, "sidebar width should clamp to its minimum")
    }
}
