import SwiftUI

/// Horizontal tab strip for the selected group, rendered inside the titlebar
/// above the terminal area (Ghostty `macos-titlebar-style = tabs`). Each tab is
/// a terminal (⌘T adds one; the × or ⌘W closes one). Tabs divide the available
/// width equally — 2 tabs → 50% each — so the strip always fills the area.
struct TabStrip: View {
    @Bindable var model: AppModel
    @Bindable var group: TabGroup

    /// Below this per-tab width the strip scrolls instead of shrinking further.
    private let minTabWidth: CGFloat = 120
    /// Fixed leading/trailing padding, inter-item spacing, and "+" button width.
    /// Kept in sync with the layout below so the tabs fill the strip exactly
    /// (content width == viewport width) before overflow scrolling kicks in.
    private let leadingPad: CGFloat = 6
    private let trailingPad: CGFloat = 8
    private let spacing: CGFloat = 4
    private let plusWidth: CGFloat = 28

    /// Measured width of the whole strip (set via a background GeometryReader).
    @State private var stripWidth: CGFloat = 0

    private var tabWidth: CGFloat {
        let count = group.tabs.count
        guard count > 0 else { return minTabWidth }
        let gaps = CGFloat(count - 1) * spacing
        let reserved = leadingPad + trailingPad + spacing + plusWidth
        let usable = max(stripWidth - reserved - gaps, 0)
        return max(usable / CGFloat(count), minTabWidth)
    }

    var body: some View {
        HStack(spacing: spacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(group.tabs) { tab in
                        TabChip(
                            title: tab.displayTitle,
                            isSelected: tab.id == group.selectedTab?.id,
                            hasUnread: tab.hasUnread,
                            select: { model.select(tab: tab, in: group) },
                            close: { model.close(tab, in: group) }
                        )
                        .frame(width: tabWidth)
                    }
                }
                .frame(maxHeight: .infinity)
            }

            Button(action: { model.newHorizontalTab() }) {
                Image(systemName: "plus")
                    .frame(width: plusWidth)
            }
            .buttonStyle(.plain)
            .help("New horizontal tab (⌘T)")
            .accessibilityIdentifier("tabstrip.newTab")
        }
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        // Transparent so the native titlebar shows through and stays draggable
        // in the gaps between tabs.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width, initial: true) { _, w in
                        stripWidth = w
                    }
            }
        )
    }
}

private struct TabChip: View {
    let title: String
    let isSelected: Bool
    /// This tab has an unread notification → show a dot.
    let hasUnread: Bool
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
            .accessibilityIdentifier("tabstrip.tab.close")

            Text(title)
                .lineLimit(1)
                .truncationMode(.head)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)

            if hasUnread && !isSelected {
                UnreadDot()
            }
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
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("tabstrip.tab")
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "selected" : (hasUnread ? "unread" : "unselected"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Shared active/hover fill color for both horizontal (`TabChip`, fully-rounded
/// capsule) and vertical (`SidebarRow`, 6pt rounded rect) tabs: light grey when active.
enum TabHighlight {
    static let shape = Capsule()

    static func fill(isSelected: Bool, hovering: Bool) -> Color {
        if isSelected { return Color.white.opacity(0.16) }
        if hovering { return Color.white.opacity(0.07) }
        return Color.clear
    }
}

/// A small accent dot marking an unread notification, shared by the sidebar rows
/// and the horizontal tab chips.
struct UnreadDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
    }
}
