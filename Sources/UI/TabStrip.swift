import SwiftUI

/// Horizontal tab strip for the selected group, rendered inside the titlebar
/// above the terminal area (Ghostty `macos-titlebar-style = tabs`). Each tab is
/// a terminal (⌘T adds one; the × or ⌘W closes one). Tabs divide the available
/// width equally — 2 tabs → 50% each — so the strip always fills the area.
struct TabStrip: View {
    @Bindable var model: AppModel
    @Bindable var group: TabGroup

    var body: some View {
        HStack(spacing: 4) {
            ForEach(group.tabs) { tab in
                TabChip(
                    title: tab.displayTitle,
                    isSelected: tab.id == group.selectedTab?.id,
                    select: { model.select(tab: tab, in: group) },
                    close: { model.close(tab, in: group) }
                )
            }

            Button(action: { model.newHorizontalTab() }) {
                Image(systemName: "plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            .help("New horizontal tab (⌘T)")
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        // Transparent so the native titlebar shows through and stays draggable
        // in the gaps between tabs.
        .background(Color.clear)
    }
}

private struct TabChip: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            // Close button on the leading edge.
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(hovering || isSelected ? 1 : 0)
            .help("Close tab (⌘W)")

            Text(title)
                .lineLimit(1)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // Fill the equal share the parent HStack hands each chip so the pill
        // background stretches (2 tabs → 50% each).
        .frame(minWidth: 60, maxWidth: .infinity)
        .background(TabHighlight.shape.fill(TabHighlight.fill(isSelected: isSelected, hovering: hovering)))
        .contentShape(Capsule())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}

/// Shared active/hover styling for both horizontal (`TabChip`) and vertical
/// (`SidebarRow`) tabs: a fully-rounded capsule, light grey when active.
enum TabHighlight {
    static let shape = Capsule()

    static func fill(isSelected: Bool, hovering: Bool) -> Color {
        if isSelected { return Color.white.opacity(0.16) }
        if hovering { return Color.white.opacity(0.07) }
        return Color.clear
    }
}
