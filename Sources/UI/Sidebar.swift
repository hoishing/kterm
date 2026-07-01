import SwiftUI

/// Vertical tab column. Each row is a group (⌘N adds one).
struct Sidebar: View {
    @Bindable var model: AppModel

    /// Drives the ⌘-hold shortcut-hint pills (⌘1, ⌘2, …) on each row.
    @State private var cmdHold = CmdHoldMonitor()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                        SidebarRow(
                            title: group.displayTitle,
                            branch: group.branch,
                            isSelected: group.id == model.selectedGroup?.id,
                            // Only the first 9 groups have a ⌘-digit shortcut.
                            shortcutNumber: index < 9 ? index + 1 : nil,
                            showsShortcutHint: cmdHold.isShowing,
                            select: { model.select(group: group) }
                        )
                    }
                }
                .padding(6)
            }

            Divider()

            Button(action: { model.newVerticalTab() }) {
                Label("New Tab", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help("New vertical tab (⌘N)")
            .accessibilityIdentifier("sidebar.newTab")
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // `.contain` makes the VStack itself an addressable accessibility
        // element (for reading its frame, e.g. in resize tests) while still
        // exposing its row/button children individually.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar")
        .onAppear { cmdHold.start() }
        .onDisappear { cmdHold.stop() }
    }
}

private struct SidebarRow: View {
    let title: String
    /// Git branch of the tab's folder, if any — shown under the title.
    let branch: String?
    let isSelected: Bool
    /// This row's ⌘-digit shortcut (1–9), or `nil` past the 9th tab.
    let shortcutNumber: Int?
    /// Whether the ⌘-hold hint pill should currently be visible.
    let showsShortcutHint: Bool
    let select: () -> Void

    /// Sidebar rows don't otherwise set an explicit title size, so pin one
    /// here purely so the branch line below has a stable "2pt smaller" to
    /// size against.
    private static let titleFontSize: CGFloat = 13

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Self.titleFontSize))
                    .lineLimit(1)
                    .truncationMode(.head)
                if let branch {
                    Text(branch)
                        .font(.system(size: Self.titleFontSize - 2))
                        .foregroundStyle(Color(red: 180 / 255, green: 141 / 255, blue: 173 / 255))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(TabHighlight.fill(isSelected: isSelected, hovering: false)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if showsShortcutHint, let shortcutNumber {
                ShortcutHintPill(number: shortcutNumber)
                    .padding(4)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsShortcutHint)
        .accessibilityIdentifier("sidebar.row")
        .accessibilityValue(isSelected ? "selected" : "unselected")
    }
}
