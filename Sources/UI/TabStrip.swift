import SwiftUI

/// Horizontal tab strip for the selected group. Each tab is a terminal
/// (⌘T adds one; the × or ⌘W closes one).
struct TabStrip: View {
    @Bindable var model: AppModel
    @Bindable var group: TabGroup

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(group.tabs) { tab in
                        TabChip(
                            title: tab.displayTitle,
                            isSelected: tab.id == group.selectedTab?.id,
                            select: { model.select(tab: tab, in: group) },
                            close: { model.close(tab, in: group) }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }

            Button(action: { model.newHorizontalTab() }) {
                Image(systemName: "plus")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .help("New horizontal tab (⌘T)")
        }
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TabChip: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .font(.system(size: 12))
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(hovering || isSelected ? 1 : 0)
            .help("Close tab (⌘W)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: 180)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}
