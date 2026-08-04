import SwiftUI

/// The window layout: the vertical tab sidebar on the left and the active
/// terminal on the right. The sidebar column extends to the top of the window
/// (hosting the traffic lights on its dark background). The content column
/// keeps a slim top drag strip instead of a full titlebar.
struct RootView: View {
    let model: AppModel

    /// Sidebar width; seeded from config and adjustable by dragging its edge.
    @State private var sidebarWidth: CGFloat
    /// Sidebar width captured at the start of a resize drag.
    @State private var dragStartWidth: CGFloat?

    /// Height of the drag strip above the sidebar (clears the traffic lights).
    private let titlebarHeight: CGFloat = 38
    /// Slim top padding / drag strip above the terminal content.
    private let contentTopPadding: CGFloat = 20
    /// Leading space the traffic lights need when the sidebar is hidden.
    private let trafficLightInset: CGFloat = 72
    private let minSidebar: CGFloat = 120
    private let maxSidebar: CGFloat = 480

    init(model: AppModel, sidebarWidth: CGFloat) {
        self.model = model
        _sidebarWidth = State(initialValue: sidebarWidth)
    }

    /// Top inset on the content column. With the sidebar shown the traffic
    /// lights sit over the sidebar, so content only needs a slim drag strip;
    /// with it hidden, keep a full titlebar height so they don't cover the
    /// terminal.
    private var contentTopHeight: CGFloat {
        model.sidebarVisible ? contentTopPadding : titlebarHeight
    }

    /// The terminal's background, reused for the drag strip above it so the
    /// chrome and terminal read as one continuous surface.
    private var terminalColor: Color { Color(nsColor: model.ghostty.backgroundColor) }

    var body: some View {
        // Two full-height columns: sidebar bg runs under the traffic lights;
        // content keeps a slim top drag strip. WindowDragArea always gets an
        // explicit width×height (same as the pre-refactor titlebar) so the
        // NSView cannot expand and paint over the sidebar list.
        HStack(spacing: 0) {
            if model.sidebarVisible {
                VStack(spacing: 0) {
                    WindowDragArea(color: .windowBackgroundColor)
                        .frame(width: sidebarWidth, height: titlebarHeight)
                    Sidebar(model: model)
                        .frame(width: sidebarWidth)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()
                resizeHandle
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if !model.sidebarVisible {
                        WindowDragArea(color: model.ghostty.backgroundColor)
                            .frame(width: trafficLightInset, height: contentTopHeight)
                    }
                    WindowDragArea(color: model.ghostty.backgroundColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: contentTopHeight)
                }
                .frame(maxWidth: .infinity)
                .frame(height: contentTopHeight)

                if let term = model.selectedTab {
                    SurfaceContainer(terminal: term)
                        .id(term.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay { AttentionBorder(active: term.showAttention) }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator(model: model))
        .overlay(alignment: .bottomTrailing) { uiTestDragSource }
        .overlay(alignment: .topTrailing) { uiTestLigatureProbe }
        .overlay(alignment: .topLeading) {
            DockBounceProbe(count: model.dockAttentionRequests).frame(width: 1, height: 1)
        }
    }

    /// A UI-test-only probe exposing the effective `kterm-font-ligatures` value,
    /// present only when launched with `KTERM_UITEST_CONFIG`. libghostty renders
    /// the terminal as one opaque surface, so the toggle's effect on glyphs isn't
    /// reachable through the accessibility tree; this surfaces the parsed setting
    /// instead (see `FontLigatureTests`). Compiled out of release builds.
    @ViewBuilder private var uiTestLigatureProbe: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KTERM_UITEST_CONFIG"] != nil {
            // The state is encoded in the identifier (`.on`/`.off`) rather than
            // an accessibility value: XCUITest doesn't surface `.value` for a
            // plain non-control probe element, but it does surface identifiers.
            let state = KtermConfig.load().fontLigatures ? "on" : "off"
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("config.fontLigatures.\(state)")
        }
        #endif
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

/// A colored strip that drags the window on click. Used for the chrome above
/// the sidebar and the slim strip above the terminal so the terminal keeps its
/// own mouse drags (for text selection). Implemented as an inline NSView (not a
/// background) so it reliably receives the mouse-down that starts the drag.
///
/// Callers must give it an explicit `.frame(width:height:)` (or equivalent).
/// Paint via `draw(_:)` (not `layer.backgroundColor`) so dynamic colors like
/// `.windowBackgroundColor` resolve against the current appearance.
struct WindowDragArea: NSViewRepresentable {
    var color: NSColor

    final class View: NSView {
        var color: NSColor = .clear {
            didSet { needsDisplay = true }
        }

        // SwiftUI owns the size via `.frame`; don't advertise an intrinsic size
        // that could fight the layout.
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            bounds.fill()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
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
        let view = View(frame: .zero)
        view.color = color
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? View else { return }
        view.color = color
    }
}

/// Applies one-time NSWindow tweaks that SwiftUI doesn't expose. The window is
/// NOT movable by its background — only `WindowDragArea` strips move it — so the
/// terminal keeps its own mouse drags for selection.
struct WindowConfigurator: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = false
            // Hand the window to the model so ⌘` window cycling can raise it.
            model.window = view.window
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
        container.setAccessibilityValue(terminal.showAttention ? "attention" : "idle")
        attach(terminal.surfaceView, to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let surface = terminal.surfaceView
        if surface.superview !== container {
            surface.removeFromSuperview()
            attach(surface, to: container)
        }
        // Mirror the attention-border state onto the container's accessibility
        // value ("attention"/"idle") so UI tests can observe the notification
        // border appear and clear. `RootView`'s body reads `showAttention` (via
        // `AttentionBorder`), so a change re-runs this update.
        container.setAccessibilityValue(terminal.showAttention ? "attention" : "idle")
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

/// A tiny, click-transparent AppKit accessibility element whose value is the
/// running count of dock-icon attention requests (`AppModel.dockAttentionRequests`).
/// The dock bounce itself isn't observable from XCUITest, so this lets a UI test
/// confirm a background ping bounced the dock. `hitTest` returns nil so it never
/// steals mouse events; only its accessibility value is ever read.
struct DockBounceProbe: NSViewRepresentable {
    let count: Int

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.setAccessibilityElement(true)
        view.setAccessibilityIdentifier("app.dockBounces")
        view.setAccessibilityValue(String(count))
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setAccessibilityValue(String(count))
    }
}

/// A static border around the content area, shown while the on-screen terminal
/// has an unacknowledged notification. It stays put (unlike a flash); it's
/// dismissed when the tab is acknowledged (see `Terminal.showAttention`). The
/// look copies cmux's persistent notification ring
/// (`WorkspaceAttentionCoordinator.notificationRingStyle` /
/// `PanelOverlayRingMetrics`): a systemBlue stroke with a soft glow, inset from
/// the edge. A brief fade in/out keeps the appearance and dismissal smooth
/// without pulsing.
private struct AttentionBorder: View {
    let active: Bool

    /// cmux uses `NSColor.systemBlue` for the notification ring's stroke/glow.
    private let ring = Color(nsColor: .systemBlue)

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(ring.opacity(active ? 1 : 0), lineWidth: 2.5)
            // cmux `notificationRingStyle`: glowOpacity 0.35, glowRadius 3.
            .shadow(color: ring.opacity(active ? 0.35 : 0), radius: 3)
            .padding(2)  // cmux `PanelOverlayRingMetrics.inset`.
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.15), value: active)
    }
}
