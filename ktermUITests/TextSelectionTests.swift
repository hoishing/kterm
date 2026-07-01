import AppKit
import XCTest

/// Mouse-drag text selection and ⌘C copy. libghostty owns selection and
/// clipboard writes internally (mouse events are forwarded raw via
/// `ghostty_surface_mouse_*`), so this drives real mouse events over the
/// rendered surface and checks the result on the system pasteboard rather
/// than any SwiftUI/accessibility state.
final class TextSelectionTests: KtermUITestCase {
    func testDragSelectsTextAndCommandCCopiesIt() {
        // A fresh, unique marker avoids matching stale pasteboard content.
        let marker = "KTERME2E\(UInt32.random(in: 0..<UInt32.max))"

        typeInTerminal("clear")
        typeInTerminal(marker, pressReturn: false)
        Thread.sleep(forTimeInterval: 0.3)

        NSPasteboard.general.clearContents()

        // Drag across the full width of the top row (the prompt line, right
        // after `clear`) so the marker is captured regardless of prompt width.
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.03))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.03))
        start.press(forDuration: 0.1, thenDragTo: end)

        app.typeKey("c", modifierFlags: .command)

        let deadline = Date().addingTimeInterval(5)
        var copied = ""
        while Date() < deadline {
            copied = NSPasteboard.general.string(forType: .string) ?? ""
            if copied.contains(marker) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertTrue(copied.contains(marker), "expected copied text to contain \(marker), got: \(copied)")
    }
}
