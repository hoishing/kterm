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
                            git: group.git,
                            isSelected: group.id == model.selectedGroup?.id,
                            hasUnread: group.hasUnread,
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
    /// Git branch + status of the tab's folder, if any — shown under the title.
    /// `nil` still reserves the same second-line height as a real branch.
    let git: GitBranch.Info?
    let isSelected: Bool
    /// Any tab in this group has an unread notification → show a dot.
    let hasUnread: Bool
    /// This row's ⌘-digit shortcut (1–9), or `nil` past the 9th tab.
    let shortcutNumber: Int?
    /// Whether the ⌘-hold hint pill should currently be visible.
    let showsShortcutHint: Bool
    let select: () -> Void

    /// Sidebar rows don't otherwise set an explicit title size, so pin one
    /// here purely so the branch line below has a stable "2pt smaller" to
    /// size against.
    private static let titleFontSize: CGFloat = 13
    /// Branch name stays purple (prior sidebar accent).
    private static let branchColor = Color(red: 180 / 255, green: 141 / 255, blue: 173 / 255)
    /// Status brackets use Ghostty Default Style Dark palette 1 (ANSI red).
    private static let statusColor = Color(red: 0xCC / 255, green: 0x65 / 255, blue: 0x66 / 255)

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: Self.titleFontSize))
                        .lineLimit(1)
                        .truncationMode(.head)
                    // Always reserve the branch line so rows inside/outside a
                    // git repo share the same height. Starship-style:
                    // `main` or `main [!?]` / `main [⇡]`.
                    gitLine
                        .font(.system(size: Self.titleFontSize - 2))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(git == nil ? 0 : 1)
                }
                Spacer(minLength: 0)
                // Persists even when the group is selected; cleared only by
                // interacting with the content area (see `Terminal.hasUnread`).
                if hasUnread {
                    UnreadDot()
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
        // Unread takes precedence over selected: with dismiss-on-interaction, a
        // group can be both selected and unread until the user interacts.
        .accessibilityValue(hasUnread ? "unread" : (isSelected ? "selected" : "unselected"))
    }

    /// `branch` in purple, optional ` [status]` in theme red. Placeholder when
    /// `git == nil` so the row still reserves second-line height.
    @ViewBuilder
    private var gitLine: some View {
        if let git {
            HStack(spacing: 0) {
                Text(git.name)
                    .foregroundStyle(Self.branchColor)
                if !git.status.isEmpty {
                    Text(" [\(git.status)]")
                        .foregroundStyle(Self.statusColor)
                }
            }
        } else {
            Text(" ")
                .foregroundStyle(Self.branchColor)
        }
    }
}
