import SwiftUI

/// The window layout: the vertical tab sidebar on the left and the active
/// terminal on the right. The selected group's horizontal tab strip sits in the
/// titlebar above the terminal area only; the sidebar column extends up into the
/// titlebar's left to host the macOS traffic-light buttons.
struct RootView: View {
    let model: AppModel

    /// Sidebar width; seeded from config and adjustable by dragging its edge.
    /// Re-seeded from `ghostty.ktermConfig` when the config is reloaded.
    @State private var sidebarWidth: CGFloat = 160
    /// Sidebar width captured at the start of a resize drag.
    @State private var dragStartWidth: CGFloat?
    /// Tracks the last applied config width so reload re-seeds only when the
    /// config value actually changed (a drag-resize shouldn't be clobbered).
    @State private var lastConfigWidth: CGFloat = 160

    /// Titlebar height; matches `TabStrip`'s bar height.
    private let titlebarHeight: CGFloat = 38
    /// Leading space the traffic lights need when the sidebar is hidden.
    private let trafficLightInset: CGFloat = 72
    private let minSidebar: CGFloat = 120
    private let maxSidebar: CGFloat = 480

    init(model: AppModel) {
        self.model = model
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

                if let tab = model.selectedGroup?.selectedTab {
                    SplitTreeView(
                        tab: tab,
                        backgroundColor: terminalColor,
                        onResize: { node, ratio in
                            model.resizeSplit(node, to: ratio, in: tab)
                        },
                        onEqualize: {
                            model.equalizeSplits(in: tab)
                        }
                    )
                    .id(tab.id)
                } else {
                    emptyState
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator(model: model))
        .overlay(alignment: .bottomTrailing) { uiTestDragSource }
        .overlay(alignment: .topTrailing) { uiTestLigatureProbe }
        .overlay(alignment: .topLeading) {
            DockBounceProbe(count: model.dockAttentionRequests).frame(width: 1, height: 1)
        }
        .onAppear { syncSidebarWidth(force: true) }
        .onChange(of: model.ghostty.ktermConfig.sidebarWidth) { syncSidebarWidth() }
    }

    /// Re-seed the sidebar width from config when the configured value
    /// changes (e.g. after ⌘⇧, reload), without clobbering a drag-resize.
    /// `force` applies unconditionally (initial appearance).
    private func syncSidebarWidth(force: Bool = false) {
        let w = model.ghostty.ktermConfig.sidebarWidth
        guard force || w != lastConfigWidth else { return }
        lastConfigWidth = w
        sidebarWidth = min(max(w, minSidebar), maxSidebar)
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
            let cfg = model.ghostty.ktermConfig
            let liga = cfg.fontLigatures ? "on" : "off"
            // Encode the family in the identifier so UI tests can assert the
            // parsed `kterm-ui-font-family` without reaching into Swift state.
            let family = cfg.uiFontFamily.isEmpty ? "monospace" : cfg.uiFontFamily
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("config.fontLigatures.\(liga)")
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("config.uiFontFamily.\(family)")
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
            .overlay(
                Text("No terminal")
                    .font(KtermUIFont.font(size: 13))
                    .foregroundStyle(.secondary)
            )
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
    let model: AppModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = false
            // Hand the window to the model so it can be raised (focus, notifications).
            model.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Hosts a terminal's persistent `SurfaceView` without recreating it on tab
/// switches or split-tree rebuilds (which would kill the shell session).
///
/// The `SurfaceView` is owned by the `Terminal` model and reparented into this
/// representable's host view. Size is driven by a `GeometryReader` so libghostty
/// gets the destination size even when AppKit hasn't finished laying out the
/// new host (same approach as Ghostty's `SurfaceRepresentable`).
///
/// **Ownership rule:** only `makeNSView` (or an orphan reclaim) may attach the
/// surface. During SwiftUI identity transitions the old and new representable
/// briefly coexist; if `updateNSView` re-attached whenever
/// `superview !== host`, the dying host would steal the surface back from the
/// new one and leave a blank pane after zoom / close-sibling / nested split.
struct SurfaceContainer: View {
    let terminal: Terminal
    var wantsFocus: Bool = false

    var body: some View {
        GeometryReader { geo in
            SurfaceRepresentable(
                terminal: terminal,
                size: geo.size,
                wantsFocus: wantsFocus
            )
        }
    }
}

private struct SurfaceRepresentable: NSViewRepresentable {
    let terminal: Terminal
    let size: CGSize
    let wantsFocus: Bool

    func makeNSView(context: Context) -> SurfaceHostView {
        let host = SurfaceHostView()
        host.setAccessibilityElement(true)
        host.setAccessibilityIdentifier("terminal.surface")
        host.setAccessibilityValue(terminal.showAttention ? "attention" : "idle")
        attach(terminal.surfaceView, to: host, size: size)
        return host
    }

    func updateNSView(_ host: SurfaceHostView, context: Context) {
        let surface = terminal.surfaceView

        if surface.superview === host {
            host.apply(size: size, to: surface)
        } else if surface.superview == nil {
            // Host was destroyed without a replacement taking ownership (e.g.
            // tab close/reopen edge cases). Reclaim the orphaned surface.
            attach(surface, to: host, size: size)
        }
        // else: another live host owns this surface — do not steal it back.

        // Mirror the attention-border state onto the host's accessibility value
        // ("attention"/"idle") so UI tests can observe the notification border
        // appear and clear. `RootView`'s body reads `showAttention` (via
        // `AttentionBorder`), so a change re-runs this update.
        host.setAccessibilityValue(terminal.showAttention ? "attention" : "idle")

        // Only the focused pane should take first responder, and only once it
        // actually owns the surface.
        if wantsFocus, surface.superview === host {
            DispatchQueue.main.async {
                guard surface.superview === host else { return }
                surface.window?.makeFirstResponder(surface)
            }
        }
    }

    private func attach(_ surface: SurfaceView, to host: SurfaceHostView, size: CGSize) {
        surface.removeFromSuperview()
        // Frame-based layout: Auto Layout against a SwiftUI-managed host fights
        // GeometryReader size updates after reparent.
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = [.width, .height]
        host.addSubview(surface)
        host.apply(size: size, to: surface)
    }
}

/// NSView host that keeps its `SurfaceView` sized to the SwiftUI proposal.
/// The host frame itself is owned by SwiftUI; we only size the reparented surface.
final class SurfaceHostView: NSView {
    func apply(size: CGSize, to surface: SurfaceView) {
        guard size.width > 0, size.height > 0 else { return }
        let rect = CGRect(origin: .zero, size: size)
        if surface.frame != rect {
            surface.frame = rect
        }
        // Always push size to libghostty. `setFrame` is a no-op when the frame
        // is unchanged, so a surface that previously applied 0×0 would never
        // recover via `setFrameSize` alone.
        surface.applyContentSize(size)
    }

    override func layout() {
        super.layout()
        guard let surface = subviews.first as? SurfaceView else { return }
        // Fall back to the host bounds once SwiftUI has laid us out — covers
        // the case where GeometryReader reported 0 during the first pass.
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        apply(size: size, to: surface)
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

/// A static border around a terminal pane, shown while that terminal has an
/// unacknowledged notification. It stays put (unlike a flash); it's dismissed
/// when the tab is acknowledged (see `Terminal.showAttention`). The look copies
/// cmux's persistent notification ring
/// (`WorkspaceAttentionCoordinator.notificationRingStyle` /
/// `PanelOverlayRingMetrics`): a systemBlue stroke with a soft glow, inset from
/// the edge. A brief fade in/out keeps the appearance and dismissal smooth
/// without pulsing.
struct AttentionBorder: View {
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
