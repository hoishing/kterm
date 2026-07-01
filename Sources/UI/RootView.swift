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

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar row.
            HStack(spacing: 0) {
                // Empty space above the sidebar that holds the traffic lights.
                Color.clear
                    .frame(width: titlebarLeadingWidth, height: titlebarHeight)

                if model.sidebarVisible {
                    Divider()
                }

                if let group = model.selectedGroup {
                    TabStrip(model: model, group: group)
                } else {
                    Color.clear.frame(height: titlebarHeight)
                }
            }
            .frame(height: titlebarHeight)

            Divider()

            // Content row.
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    Sidebar(model: model)
                        .frame(width: sidebarWidth)
                        .overlay(alignment: .trailing) { resizeHandle }

                    Divider()
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
    }

    /// A thin, full-height strip over the sidebar's trailing edge that resizes
    /// the sidebar on drag and shows the horizontal-resize cursor on hover.
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .offset(x: 4) // straddle the divider line
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartWidth ?? sidebarWidth
                        if dragStartWidth == nil { dragStartWidth = start }
                        sidebarWidth = min(max(start + value.translation.width, minSidebar), maxSidebar)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }

    private var emptyState: some View {
        Color(nsColor: .textBackgroundColor)
            .overlay(Text("No terminal").foregroundStyle(.secondary))
    }
}

/// Applies one-time NSWindow tweaks that SwiftUI doesn't expose: keep the
/// window draggable from the empty titlebar/gap regions now that our own view
/// fills the (hidden) titlebar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = true
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
