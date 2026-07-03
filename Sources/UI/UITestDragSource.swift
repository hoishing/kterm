#if DEBUG
import AppKit
import SwiftUI

/// A UI-test-only draggable square, present only when the app is launched with
/// `KTERM_UITEST_DRAG_PATH` set (see `DragImageDropTests`). Dropping a real file
/// onto the terminal from Finder can't be scripted reliably by XCUITest, so
/// instead this view starts a genuine AppKit dragging session that vends the
/// given file URL. An XCUITest `press(thenDragTo:)` from here onto the surface
/// then drives `SurfaceView`'s real `performDragOperation`. Never shown in
/// normal use — its overlay is gated on the env var in `RootView`.
struct UITestDragSource: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> NSView {
        let view = SourceView()
        view.fileURL = fileURL
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityIdentifier("uitest.dragSource")
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SourceView)?.fileURL = fileURL
    }

    final class SourceView: NSView, NSDraggingSource {
        var fileURL: URL?

        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setFill()
            dirtyRect.fill()
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        override func mouseDown(with event: NSEvent) {
            guard let fileURL else { return }
            // NSURL writes the `.fileURL` pasteboard type, which SurfaceView's
            // drop handler reads back via `readObjects(forClasses: [NSURL.self])`.
            let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
            item.setDraggingFrame(bounds, contents: nil)
            beginDraggingSession(with: [item], event: event, source: self)
        }
    }
}
#endif
