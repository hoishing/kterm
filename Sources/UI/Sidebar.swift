import SwiftUI

/// Vertical tab column. Each row is a group (⌘N adds one).
struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.groups) { group in
                        SidebarRow(
                            title: group.displayTitle,
                            isSelected: group.id == model.selectedGroup?.id,
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
    }
}

private struct SidebarRow: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TabHighlight.shape.fill(TabHighlight.fill(isSelected: isSelected, hovering: false)))
                .contentShape(TabHighlight.shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.row")
        .accessibilityValue(isSelected ? "selected" : "unselected")
    }
}
