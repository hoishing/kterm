import SwiftUI

/// Vertical tab column. Each row is a group (⌘N adds one).
struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                        SidebarRow(
                            title: group.displayTitle,
                            isSelected: group.id == model.selectedGroup?.id,
                            tabCount: group.tabs.count,
                            shortcutNumber: index + 1,
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
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarRow: View {
    let title: String
    let isSelected: Bool
    let tabCount: Int
    /// 1-based position; shown as a ⌘N hint for the first nine groups.
    let shortcutNumber: Int
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if tabCount > 1 {
                    Text("\(tabCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if shortcutNumber <= 9 {
                    Text("⌘\(shortcutNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TabHighlight.shape.fill(TabHighlight.fill(isSelected: isSelected, hovering: false)))
            .contentShape(TabHighlight.shape)
        }
        .buttonStyle(.plain)
    }
}
