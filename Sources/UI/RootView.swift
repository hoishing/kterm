import SwiftUI

/// The window layout: the vertical tab sidebar on the left and the active
/// terminal on the right. The selected group's horizontal tab strip sits in the
/// titlebar above the terminal area only; the sidebar column extends up into the
/// titlebar's left to host the macOS traffic-light buttons.
struct RootView: View {
    let model: AppModel

    /// Sidebar width; seeded from config and adjustable by dragging its edge.
    @State private var sidebarWidth: CGFloat
    /// Sidebar width captured at the start of a resize drag.
    @State private var dragStartWidth: CGFloat?

    /// Titlebar height; matches `TabStrip`'s bar height.
    private let titlebarHeight: CGFloat = 38
    /// Leading space the traffic lights need when the sidebar is hidden.
    private let trafficLightInset: CGFloat = 72
    private let minSidebar: CGFloat = 120
    private let maxSidebar: CGFloat = 480

    init(model: AppModel, sidebarWidth: CGFloat) {
        self.model = model
        _sidebarWidth = State(initialValue: sidebarWidth)
    }

    /// Left column width in the titlebar row: the sidebar when shown, otherwise
    /// just enough to clear the traffic lights.
    private var titlebarLeadingWidth: CGFloat {
        model.sidebarVisible ? sidebarWidth : trafficLightInset
    }

    /// The sidebar's background, reused for the titlebar area above it.
    private var sidebarColor: Color { Color(nsColor: .windowBackgroundColor) }
    /// The terminal's background, reused for the titlebar area above it so the
    /// tab strip and terminal read as one continuous surface.
    private var terminalColor: Color { Color(nsColor: model.ghostty.backgroundColor) }

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar row. No divider below it: the titlebar shares the
            // sidebar/terminal backgrounds so each side reads as one surface.
            HStack(spacing: 0) {
                // Empty space above the sidebar that holds the traffic lights.
                // This is the only region that drags the window (the window is
                // not movable by its background, so the terminal keeps its own
                // mouse drags for text selection).
                WindowDragArea(color: model.sidebarVisible
                    ? NSColor.windowBackgroundColor : model.ghostty.backgroundColor)
                    .frame(width: titlebarLeadingWidth, height: titlebarHeight)

                if model.sidebarVisible {
                    Divider()
                }

                Group {
                    if let group = model.selectedGroup {
                        TabStrip(model: model, group: group)
                    } else {
                        Color.clear.frame(height: titlebarHeight)
                    }
                }
                .background(terminalColor)
            }
            .frame(height: titlebarHeight)

            // Content row.
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    Sidebar(model: model)
                        .frame(width: sidebarWidth)

                    Divider()
                    resizeHandle
                }

                if let term = model.selectedGroup?.selectedTab {
                    SurfaceContainer(terminal: term)
                        .id(term.id)
                } else {
                    emptyState
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator())
        .overlay(alignment: .bottomTrailing) { uiTestDragSource }
    }

    /// A UI-test-only drag source overlaid on the terminal corner, present only
    /// when launched with `KTERM_UITEST_DRAG_PATH` (see `DragImageDropTests`).
    /// Empty — and compiled out entirely — otherwise.
    @ViewBuilder private var uiTestDragSource: some View {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["KTERM_UITEST_DRAG_PATH"] {
            UITestDragSource(fileURL: URL(fileURLWithPath: path))
                .frame(width: 44, height: 44)
                .padding(8)
        }
        #endif
    }

    /// A thin, full-height strip just right of the divider that resizes the
    /// sidebar on drag. Implemented in AppKit so its drag doesn't compete with
    /// the window's `isMovableByWindowBackground` dragging (which would otherwise
    /// move the window). Painted with the terminal background so it blends into
    /// the terminal area (no visible band beside the divider).
    private var resizeHandle: some View {
        SidebarResizeHandle(
            onChanged: { translation in
                let start = dragStartWidth ?? sidebarWidth
                if dragStartWidth == nil { dragStartWidth = start }
                sidebarWidth = min(max(start + translation, minSidebar), maxSidebar)
            },
            onEnded: { dragStartWidth = nil }
        )
        .frame(width: 8)
        .background(terminalColor)
    }

    private var emptyState: some View {
        terminalColor
            .overlay(Text("No terminal").foregroundStyle(.secondary))
    }
}

/// An AppKit-backed drag strip for resizing the sidebar. It refuses to move the
/// window (`mouseDownCanMoveWindow = false`) and reports the horizontal drag
/// translation (in window points, relative to the mouse-down point) so it works
/// even as the strip repositions during the resize.
struct SidebarResizeHandle: NSViewRepresentable {
    /// Called on drag with the total translation since the drag began.
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HandleView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityIdentifier("sidebar.resizeHandle")
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HandleView else { return }
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    final class HandleView: NSView {
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: (() -> Void)?
        private var startX: CGFloat = 0

        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseDown(with event: NSEvent) {
            startX = event.locationInWindow.x
        }

        override func mouseDragged(with event: NSEvent) {
            onChanged?(event.locationInWindow.x - startX)
        }

        override func mouseUp(with event: NSEvent) {
            onEnded?()
        }
    }
}

/// A titlebar-colored strip that drags the window on click. Used only for the
/// area above the sidebar so the terminal keeps its own mouse drags (for text
/// selection). Implemented as an inline NSView (not a background) so it reliably
/// receives the mouse-down that starts the drag.
struct WindowDragArea: NSViewRepresentable {
    var color: NSColor

    final class View: NSView {
        var color: NSColor = .clear

        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            dirtyRect.fill()
        }

        override func mouseDown(with event: NSEvent) {
            // Double-click behaves like the native titlebar (zoom); otherwise
            // start moving the window.
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = View()
        view.color = color
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? View else { return }
        view.color = color
        view.needsDisplay = true
    }
}

/// Applies one-time NSWindow tweaks that SwiftUI doesn't expose. The window is
/// NOT movable by its background — only `WindowDragArea` (the titlebar above the
/// sidebar) moves it — so the terminal keeps its own mouse drags for selection.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Hosts a terminal's persistent `SurfaceView` without recreating it on tab
/// switches (which would kill the shell session). The container reparents the
/// surface view, which stays owned by the `Terminal` model object.
struct SurfaceContainer: NSViewRepresentable {
    let terminal: Terminal

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setAccessibilityElement(true)
        container.setAccessibilityIdentifier("terminal.surface")
        attach(terminal.surfaceView, to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let surface = terminal.surfaceView
        if surface.superview !== container {
            surface.removeFromSuperview()
            attach(surface, to: container)
        }
        DispatchQueue.main.async {
            surface.window?.makeFirstResponder(surface)
        }
    }

    private func attach(_ surface: SurfaceView, to container: NSView) {
        surface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surface.topAnchor.constraint(equalTo: container.topAnchor),
            surface.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
