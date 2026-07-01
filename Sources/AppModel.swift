import SwiftUI
import Observation

/// A single terminal = one libghostty surface plus its hosting view.
@Observable
@MainActor
final class Terminal: Identifiable {
    let id = UUID()
    var title: String = ""
    let surfaceView: SurfaceView

    init(app: GhosttyApp) {
        // `app.app` is guaranteed non-nil once the app launched successfully.
        self.surfaceView = SurfaceView(app: app.app!)
    }

    /// A short label for the tab strip.
    var displayTitle: String { title.isEmpty ? "Terminal" : title }
}

/// A vertical (sidebar) tab: a named group of horizontal terminal tabs.
@Observable
@MainActor
final class TabGroup: Identifiable {
    let id = UUID()
    var tabs: [Terminal] = []
    var selectedTabID: UUID?

    var selectedTab: Terminal? {
        tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    /// Group title mirrors the active terminal.
    var displayTitle: String { selectedTab?.displayTitle ?? "Terminal" }
}

/// The whole window state: a list of vertical tabs (groups), each containing
/// horizontal tabs (terminals). No splits — just two levels of tabs.
@Observable
@MainActor
final class AppModel {
    var groups: [TabGroup] = []
    var selectedGroupID: UUID?

    let ghostty: GhosttyApp

    var selectedGroup: TabGroup? {
        groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    init(ghostty: GhosttyApp) {
        self.ghostty = ghostty
        // Start with one vertical tab containing one terminal.
        newVerticalTab()
    }

    /// ⌘N — new vertical tab (a fresh group with one terminal), selected.
    func newVerticalTab() {
        guard ghostty.app != nil else { return }
        let group = TabGroup()
        let term = makeTerminal()
        group.tabs.append(term)
        group.selectedTabID = term.id
        groups.append(group)
        selectedGroupID = group.id
    }

    /// ⌘T — new horizontal tab (a terminal in the current group), selected.
    func newHorizontalTab() {
        guard ghostty.app != nil else { return }
        guard let group = selectedGroup else { newVerticalTab(); return }
        let term = makeTerminal()
        group.tabs.append(term)
        group.selectedTabID = term.id
    }

    /// ⌘W — close the active horizontal tab. If the group empties, drop it; if
    /// the last group goes, close the window.
    func closeActiveTab() {
        guard let group = selectedGroup, let term = group.selectedTab else { return }
        close(term, in: group)
    }

    func select(group: TabGroup) {
        selectedGroupID = group.id
        focusSelected()
    }

    /// ⌘1…⌘9 — select the vertical tab (group) at `index`, if it exists.
    func selectGroup(at index: Int) {
        guard index >= 0, index < groups.count else { return }
        select(group: groups[index])
    }

    /// ⌘⇧] / ⌘⇧[ — cycle horizontal tabs within the selected group (wrapping).
    func selectNextHorizontalTab() { cycleHorizontal(+1) }
    func selectPrevHorizontalTab() { cycleHorizontal(-1) }

    private func cycleHorizontal(_ delta: Int) {
        guard let group = selectedGroup, !group.tabs.isEmpty,
              let cur = group.tabs.firstIndex(where: { $0.id == group.selectedTab?.id })
        else { return }
        let next = (cur + delta + group.tabs.count) % group.tabs.count
        select(tab: group.tabs[next], in: group)
    }

    /// ⌃⇧] / ⌃⇧[ — cycle vertical tabs (groups) (wrapping).
    func selectNextVerticalTab() { cycleVertical(+1) }
    func selectPrevVerticalTab() { cycleVertical(-1) }

    private func cycleVertical(_ delta: Int) {
        guard !groups.isEmpty,
              let cur = groups.firstIndex(where: { $0.id == selectedGroup?.id })
        else { return }
        let next = (cur + delta + groups.count) % groups.count
        select(group: groups[next])
    }

    func select(tab: Terminal, in group: TabGroup) {
        selectedGroupID = group.id
        group.selectedTabID = tab.id
        focusSelected()
    }

    func close(_ term: Terminal, in group: TabGroup) {
        guard let idx = group.tabs.firstIndex(where: { $0.id == term.id }) else { return }
        group.tabs.remove(at: idx)

        if group.tabs.isEmpty {
            // Drop the now-empty group, selecting a neighbour.
            let gIdx = groups.firstIndex { $0.id == group.id } ?? 0
            groups.remove(at: gIdx)
            if groups.isEmpty {
                // No terminals left: close the window.
                NSApp.keyWindow?.close()
                return
            }
            selectedGroupID = groups[min(gIdx, groups.count - 1)].id
        } else {
            // Select a neighbouring tab.
            group.selectedTabID = group.tabs[min(idx, group.tabs.count - 1)].id
        }
        focusSelected()
    }

    private func makeTerminal() -> Terminal {
        let term = Terminal(app: ghostty)
        term.surfaceView.onTitleChange = { [weak term] title in
            term?.title = title
        }
        term.surfaceView.onClose = { [weak self, weak term] in
            guard let self, let term else { return }
            // Find which group holds it and close.
            for group in self.groups where group.tabs.contains(where: { $0.id == term.id }) {
                self.close(term, in: group)
                return
            }
        }
        return term
    }

    /// Make the selected terminal's view first responder so typing goes to it.
    private func focusSelected() {
        guard let view = selectedGroup?.selectedTab?.surfaceView else { return }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}
