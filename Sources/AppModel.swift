import AppKit
import SwiftUI
import Observation

/// A single terminal = one libghostty surface plus its hosting view.
@Observable
@MainActor
final class Terminal: Identifiable {
    let id = UUID()
    var title: String = ""
    /// Current working directory reported by the shell, if any.
    var pwd: String = ""
    /// Git branch of `pwd`, if it's inside a repo (refreshed on `pwd` change
    /// and whenever this tab regains focus, so `git checkout` in-shell shows
    /// up too). `nil` outside a repo or in detached HEAD.
    var branch: String?
    let surfaceView: SurfaceView

    init(app: GhosttyApp) {
        // `app.app` is guaranteed non-nil once the app launched successfully.
        // `id` (a stored `let` with a default) is already initialized here, so
        // the surface can be tagged with this tab's id via `KTERM_TAB_ID`.
        self.surfaceView = SurfaceView(app: app.app!, tabID: id)
    }

    /// A label for the tab strip: the working directory path relative to
    /// home (`~/...`), or the full path if outside home, falling back to
    /// the title, then "Terminal". Views truncate this from the front
    /// (`.truncationMode(.head)`) so the trailing folder always stays visible.
    var displayTitle: String {
        if let path = Self.displayPath(for: pwd) { return path }
        return title.isEmpty ? "Terminal" : title
    }

    /// The directory path with the home directory abbreviated to `~`.
    /// Returns nil for an empty path.
    private static func displayPath(for path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
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

    /// Git branch shown under the folder title in the sidebar, mirroring the
    /// active terminal's `pwd`.
    var branch: String? { selectedTab?.branch }
}

/// The whole window state: a list of vertical tabs (groups), each containing
/// horizontal tabs (terminals). No splits — just two levels of tabs.
@Observable
@MainActor
final class AppModel {
    var groups: [TabGroup] = []
    var selectedGroupID: UUID?

    /// Whether the vertical tab sidebar is shown (⌘B toggles it).
    var sidebarVisible = true

    let ghostty: GhosttyApp

    /// The single live model, so `AppDelegate` (which owns the notification
    /// delegate) can route a notification tap back to it.
    static weak var shared: AppModel?

    var selectedGroup: TabGroup? {
        groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    init(ghostty: GhosttyApp) {
        self.ghostty = ghostty
        Self.shared = self
        // Start with one vertical tab containing one terminal.
        newVerticalTab()

        // Re-check the selected tab's branch when kterm regains focus, so an
        // in-shell `git checkout` made while another app was frontmost shows
        // up as soon as the user comes back.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, let term = self.selectedGroup?.selectedTab else { return }
                self.refreshBranch(for: term)
            }
        }
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
        if let term = group.selectedTab { refreshBranch(for: term) }
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

    /// ⌘⌃] / ⌘⌃[ — cycle vertical tabs (groups) (wrapping).
    func selectNextVerticalTab() { cycleVertical(+1) }
    func selectPrevVerticalTab() { cycleVertical(-1) }

    private func cycleVertical(_ delta: Int) {
        guard !groups.isEmpty,
              let cur = groups.firstIndex(where: { $0.id == selectedGroup?.id })
        else { return }
        let next = (cur + delta + groups.count) % groups.count
        select(group: groups[next])
    }

    /// Bring kterm to the front and focus the tab that raised a desktop
    /// notification, restoring the window if it was minimized. No-op if the
    /// tab has since closed.
    func focusTerminal(withID id: UUID) {
        for group in groups {
            guard let tab = group.tabs.first(where: { $0.id == id }) else { continue }
            NSApp.activate(ignoringOtherApps: true)
            if let window = tab.surfaceView.window {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
            select(tab: tab, in: group)
            return
        }
    }

    func select(tab: Terminal, in group: TabGroup) {
        selectedGroupID = group.id
        group.selectedTabID = tab.id
        focusSelected()
        refreshBranch(for: tab)
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
        term.surfaceView.onPwdChange = { [weak self, weak term] pwd in
            term?.pwd = pwd
            if let term { self?.refreshBranch(for: term) }
        }
        term.surfaceView.onNotification = { [weak self, weak term] title, body in
            guard let self, let term else { return }
            // Suppress only when kterm is frontmost AND this exact tab is
            // the one currently visible — otherwise the user isn't looking
            // at it and should be told.
            let isFocused = NSApp.isActive && self.selectedGroup?.selectedTab?.id == term.id
            guard !isFocused else { return }
            NotificationManager.post(title: title, body: body, terminalID: term.id)
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

    /// Re-resolves `term`'s git branch from its current `pwd`, off the main
    /// thread. Guards against races (pwd changing again mid-lookup, or the
    /// terminal closing) by re-checking `pwd` before writing back.
    private func refreshBranch(for term: Terminal) {
        let pwd = term.pwd
        Task { @MainActor [weak term] in
            let branch = await GitBranch.current(for: pwd)
            guard let term, term.pwd == pwd else { return }
            term.branch = branch
        }
    }

    /// Make the selected terminal's view first responder so typing goes to it.
    private func focusSelected() {
        guard let view = selectedGroup?.selectedTab?.surfaceView else { return }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}
