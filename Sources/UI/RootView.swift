import SwiftUI

/// The window layout: vertical tab sidebar on the left, and on the right the
/// selected group's horizontal tab strip above its active terminal.
struct RootView: View {
    @Bindable var model: AppModel
    let sidebarWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
                .frame(width: sidebarWidth)

            Divider()

            VStack(spacing: 0) {
                if let group = model.selectedGroup {
                    TabStrip(model: model, group: group)
                    Divider()
                    if let term = group.selectedTab {
                        SurfaceContainer(terminal: term)
                            .id(term.id)
                    } else {
                        emptyState
                    }
                } else {
                    emptyState
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    private var emptyState: some View {
        Color(nsColor: .textBackgroundColor)
            .overlay(Text("No terminal").foregroundStyle(.secondary))
    }
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
