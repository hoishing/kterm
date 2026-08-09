import AppKit
import SwiftUI
import Observation
import GhosttyKit

/// A single terminal = one libghostty surface plus its hosting view.
@Observable
@MainActor
final class Terminal: Identifiable {
    let id = UUID()
    var title: String = ""
    /// Current working directory reported by the shell, if any.
    var pwd: String = ""
    /// Git branch + Starship-style status of `pwd`, if it's inside a repo
    /// (refreshed on `pwd` change and whenever this tab regains focus, so
    /// `git checkout` / dirty worktree changes show up too). `nil` outside a
    /// repo or in detached HEAD.
    var git: GitBranch.Info?
    let surfaceView: SurfaceView

    /// Has an unread notification/bell that the user hasn't acknowledged yet.
    /// Set whenever a bell or OSC 9/777 notification arrives for this tab —
    /// even while it's frontmost-visible, mirroring cmux; drives the sidebar
    /// row's dot and the horizontal tab's 🔔. Cleared, together with
    /// `showAttention`, when the tab is selected, when kterm returns to the
    /// foreground, or when the user interacts with its content area — a
    /// keystroke or click (see `AppModel.acknowledge`).
    var hasUnread = false

    /// True while this on-screen terminal has an unacknowledged notification,
    /// drawing a static attention border around the content area (see
    /// `AttentionBorder`). Set when a notification arrives for the visible tab;
    /// cleared, together with `hasUnread`, when the tab is selected, when kterm
    /// returns to the foreground, or on content interaction (see
    /// `AppModel.acknowledge`).
    var showAttention = false

    /// - Parameter inheritFrom: the terminal whose ⌘N/⌘T/split spawned this one,
    ///   so the new surface opens in that tab's working directory. `nil` for the
    ///   very first tab.
    /// - Parameter inheritContext: libghostty context for the inherited config
    ///   (`TAB` for a new tab, `SPLIT` for a new pane).
    /// - Parameter workingDirectory: an explicit directory to open in (e.g. a
    ///   folder passed to `open -a kterm <dir>`), overriding the inherited cwd.
    init(app: GhosttyApp,
         inheritFrom parent: Terminal? = nil,
         inheritContext: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_TAB,
         workingDirectory: String? = nil) {
        // `app.app` is guaranteed non-nil once the app launched successfully.
        // `id` (a stored `let` with a default) is already initialized here, so
        // the surface can be tagged with this tab's id via `KTERM_TAB_ID`.
        self.surfaceView = SurfaceView(
            app: app.app!, tabID: id, inheritFrom: parent?.surfaceView.surface,
            inheritContext: inheritContext,
            workingDirectory: workingDirectory)
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

/// A horizontal tab: a split tree of terminals sharing one chip in the strip.
/// Ghostty's equivalent is a single tab's `surfaceTree`.
@Observable
@MainActor
final class TerminalTab: Identifiable {
    let id = UUID()
    var tree: SplitTree
    var focusedTerminalID: UUID?

    init(root: Terminal) {
        self.tree = SplitTree(terminal: root)
        self.focusedTerminalID = root.id
    }

    var focusedTerminal: Terminal? {
        tree.terminals.first { $0.id == focusedTerminalID } ?? tree.terminals.first
    }

    var terminals: [Terminal] { tree.terminals }

    /// Tab title mirrors the focused pane.
    var displayTitle: String { focusedTerminal?.displayTitle ?? "Terminal" }

    var git: GitBranch.Info? { focusedTerminal?.git }

    /// Any pane has an unread notification → the chip shows a 🔔.
    var hasUnread: Bool { terminals.contains { $0.hasUnread } }

    /// A pane is zoomed to fill this tab (Ghostty `toggle_split_zoom`).
    var isZoomed: Bool { tree.zoomed != nil }
}

/// A vertical (sidebar) tab: a named group of horizontal tabs.
@Observable
@MainActor
final class TabGroup: Identifiable {
    let id = UUID()
    var tabs: [TerminalTab] = []
    var selectedTabID: UUID?

    var selectedTab: TerminalTab? {
        tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    /// Group title mirrors the active horizontal tab's focused pane.
    var displayTitle: String { selectedTab?.displayTitle ?? "Terminal" }

    /// Git info shown under the folder title in the sidebar, mirroring the
    /// focused pane's `pwd`.
    var git: GitBranch.Info? { selectedTab?.git }

    /// Any pane in this group has an unread notification → the sidebar
    /// row shows an unread dot.
    var hasUnread: Bool { tabs.contains { $0.hasUnread } }
}

/// The whole window state: a list of vertical tabs (groups), each containing
/// horizontal tabs, each of which holds a split tree of terminals.
@Observable
@MainActor
final class AppModel {
    var groups: [TabGroup] = []
    var selectedGroupID: UUID?

    /// Whether the vertical tab sidebar is shown (⌘B toggles it).
    var sidebarVisible = true

    /// Count of dock-icon attention requests made (see `notify`). Exposed only
    /// so UI tests can observe that a background ping bounced the dock — the
    /// bounce itself has no accessibility surface (see `DockBounceProbe`).
    private(set) var dockAttentionRequests = 0

    let ghostty: GhosttyApp

    /// Where a new tab lands relative to the current one (`kterm-new-tab-position`).
    let newTabPosition: KtermConfig.NewTabPosition

    /// This model's NSWindow, captured once it's on screen (see
    /// `WindowConfigurator`). Used to raise/cycle windows.
    weak var window: NSWindow?

    /// Every live window's model, oldest first. Weakly held so a closed
    /// window's model drops out on its own. Lets ⌘` cycle windows and lets a
    /// notification tap reach whichever window owns the tab (`AppModel` is a
    /// per-window state, one per open window).
    private final class Box { weak var model: AppModel?; init(_ m: AppModel) { model = m } }
    private static var registry: [Box] = []
    static var all: [AppModel] { registry.compactMap(\.model) }

    /// A directory requested via `open -a kterm <dir>` before any window
    /// existed (cold launch). The first window created consumes it so its
    /// initial tab opens there instead of the default cwd.
    private static var pendingOpenDirectory: String?

    /// Opens a fresh kterm window (SwiftUI `openWindow(id:)`), wired up by
    /// `KtermCommands`. The WindowGroup declines to auto-open a window for
    /// external opens (`.handlesExternalEvents(matching:)`, so warm
    /// `open -a kterm <dir>` doesn't spawn a surplus window); this lets a cold
    /// launch still get its first window (see `openDirectory`).
    static var openNewWindow: (() -> Void)?

    var selectedGroup: TabGroup? {
        groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    init(ghostty: GhosttyApp, newTabPosition: KtermConfig.NewTabPosition = .afterCurrent) {
        self.ghostty = ghostty
        self.newTabPosition = newTabPosition
        Self.registry.removeAll { $0.model == nil }
        Self.registry.append(Box(self))
        // Start with one vertical tab containing one terminal. On a cold launch
        // via `open -a kterm <dir>` the requested folder may already be waiting;
        // consume it so the very first tab opens there.
        let pending = Self.pendingOpenDirectory
        Self.pendingOpenDirectory = nil
        newVerticalTab(workingDirectory: pending)

        // Re-check the selected tab's branch when kterm regains focus, so an
        // in-shell `git checkout` made while another app was frontmost shows
        // up as soon as the user comes back.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, let term = self.selectedGroup?.selectedTab?.focusedTerminal else { return }
                // cmux marks the selected tab's notification read when kterm
                // returns to the foreground — acknowledge it here too.
                self.acknowledge(term)
                self.refreshBranch(for: term)
            }
        }
    }

    /// ⌘N — new vertical tab (a fresh group with one terminal), selected. It
    /// opens in the current tab's working directory (see `Terminal.init`), or in
    /// `workingDirectory` when one is given (e.g. `open -a kterm <dir>`).
    func newVerticalTab(workingDirectory: String? = nil) {
        guard ghostty.app != nil else { return }
        let group = TabGroup()
        let term = makeTerminal(inheritFrom: selectedGroup?.selectedTab?.focusedTerminal,
                                workingDirectory: workingDirectory)
        let tab = TerminalTab(root: term)
        group.tabs.append(tab)
        group.selectedTabID = tab.id
        groups.insert(group, at: insertionIndex(in: groups, after: selectedGroupID))
        selectedGroupID = group.id
    }

    /// ⌘T — new horizontal tab (a terminal in the current group), selected. It
    /// opens in the current tab's working directory (see `Terminal.init`).
    func newHorizontalTab() {
        guard ghostty.app != nil else { return }
        guard let group = selectedGroup else { newVerticalTab(); return }
        let term = makeTerminal(inheritFrom: group.selectedTab?.focusedTerminal)
        let tab = TerminalTab(root: term)
        group.tabs.insert(tab, at: insertionIndex(in: group.tabs, after: group.selectedTabID))
        group.selectedTabID = tab.id
    }

    /// The slot a freshly spawned sibling should occupy. With
    /// `kterm-new-tab-position = after-current` it lands right after the tab it
    /// was spawned from (pushing the rest back); otherwise it goes to the end.
    private func insertionIndex<T: Identifiable>(in items: [T], after currentID: T.ID?) -> Int {
        guard newTabPosition == .afterCurrent, let currentID,
              let idx = items.firstIndex(where: { $0.id == currentID })
        else { return items.count }
        return idx + 1
    }

    /// ⌘W / Ghostty `close_surface` — close the focused pane. If it was the
    /// last pane in its horizontal tab, drop the tab; if that emptied the
    /// group, drop the group; if that was the last group, close the window.
    func closeFocusedSurface() {
        guard let group = selectedGroup, let tab = group.selectedTab,
              let term = tab.focusedTerminal else { return }
        close(term, in: tab, group: group)
    }

    /// Close an entire horizontal tab (all its panes). Used by the tab-chip ×.
    func close(_ tab: TerminalTab, in group: TabGroup) {
        guard let idx = group.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        group.tabs.remove(at: idx)

        if group.tabs.isEmpty {
            let gIdx = groups.firstIndex { $0.id == group.id } ?? 0
            groups.remove(at: gIdx)
            if groups.isEmpty {
                NSApp.keyWindow?.close()
                return
            }
            selectedGroupID = groups[min(gIdx, groups.count - 1)].id
        } else {
            group.selectedTabID = group.tabs[min(idx, group.tabs.count - 1)].id
        }
        focusSelected()
    }

    func select(group: TabGroup) {
        selectedGroupID = group.id
        focusSelected()
        if let term = group.selectedTab?.focusedTerminal {
            acknowledge(term)
            refreshBranch(for: term)
        }
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

    /// ⌘` — cycle key focus through kterm's windows (wrapping). No-op with
    /// fewer than two windows on screen.
    static func cycleWindow() {
        let models = all.filter { $0.window != nil }
        guard models.count > 1 else { return }
        let key = NSApp.keyWindow
        let idx = models.firstIndex { $0.window === key } ?? 0
        let next = models[(idx + 1) % models.count]
        NSApp.activate(ignoringOtherApps: true)
        next.window?.makeKeyAndOrderFront(nil)
        next.focusSelected()
    }

    /// Open `path` as a new vertical tab in the front kterm window, bringing the
    /// app forward. Used for a folder passed to `open -a kterm <dir>` (or dropped
    /// on the app icon / Finder "Open With"). If no window exists yet — a cold
    /// launch racing ahead of window creation — the path is stashed so the first
    /// window's initial tab opens there instead (see `init`).
    static func openDirectory(_ path: String) {
        guard let model = all.first(where: { $0.window === NSApp.keyWindow }) ?? all.first else {
            // Cold launch — no window exists yet, and our WindowGroup won't
            // auto-open one for an external open. Stash the folder for the first
            // window's initial tab, then ask SwiftUI to create that window.
            pendingOpenDirectory = path
            openNewWindow?()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        model.window?.makeKeyAndOrderFront(nil)
        model.newVerticalTab(workingDirectory: path)
    }

    /// Route a notification tap (or `kterm://focus-tab` URL) to whichever
    /// window owns the tab. Only the owning model reacts; the rest no-op.
    static func focusTerminalAnyWindow(withID id: UUID) {
        for model in all { model.focusTerminal(withID: id) }
    }

    /// Bring kterm to the front and focus the pane that raised a desktop
    /// notification, restoring the window if it was minimized. No-op if the
    /// pane has since closed.
    func focusTerminal(withID id: UUID) {
        for group in groups {
            for tab in group.tabs {
                guard let term = tab.terminals.first(where: { $0.id == id }) else { continue }
                NSApp.activate(ignoringOtherApps: true)
                if let window = term.surfaceView.window {
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    window.makeKeyAndOrderFront(nil)
                }
                select(tab: tab, in: group)
                focus(term, in: tab)
                return
            }
        }
    }

    func select(tab: TerminalTab, in group: TabGroup) {
        selectedGroupID = group.id
        group.selectedTabID = tab.id
        focusSelected()
        if let term = tab.focusedTerminal {
            acknowledge(term)
            refreshBranch(for: term)
        }
    }

    /// Focus a specific pane inside a horizontal tab.
    func focus(_ term: Terminal, in tab: TerminalTab) {
        tab.focusedTerminalID = term.id
        // Split/zoom rebuilds reparent the surface on the next SwiftUI pass, so
        // the view may not be in a window yet. Retry once if needed; the
        // focused `SurfaceContainer` also claims first responder on attach.
        DispatchQueue.main.async {
            if term.surfaceView.window != nil {
                term.surfaceView.window?.makeFirstResponder(term.surfaceView)
            } else {
                DispatchQueue.main.async {
                    term.surfaceView.window?.makeFirstResponder(term.surfaceView)
                }
            }
        }
        acknowledge(term)
        refreshBranch(for: term)
    }

    // MARK: - Splits (Ghostty keybinds → actions)

    /// Ghostty `new_split:*` — split the focused pane in `direction`.
    func newSplit(from surfaceView: SurfaceView, direction: ghostty_action_split_direction_e) {
        guard let (group, tab, source) = locate(surfaceView: surfaceView) else { return }

        let splitDirection: SplitTree.NewDirection
        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT: splitDirection = .right
        case GHOSTTY_SPLIT_DIRECTION_LEFT:  splitDirection = .left
        case GHOSTTY_SPLIT_DIRECTION_DOWN:  splitDirection = .down
        case GHOSTTY_SPLIT_DIRECTION_UP:    splitDirection = .up
        default: return
        }

        let newTerm = makeTerminal(inheritFrom: source,
                                   inheritContext: GHOSTTY_SURFACE_CONTEXT_SPLIT)
        do {
            tab.tree = try tab.tree.inserting(newTerm, at: source, direction: splitDirection)
            focus(newTerm, in: tab)
            // Keep the tab selected in case focus moved us around.
            group.selectedTabID = tab.id
            selectedGroupID = group.id
        } catch {
            NSLog("kterm: failed to insert split: \(error)")
        }
    }

    /// Ghostty `goto_split:*`. Returns `false` when no target exists so
    /// performable keybinds don't consume the key.
    @discardableResult
    func gotoSplit(from surfaceView: SurfaceView, direction: ghostty_action_goto_split_e) -> Bool {
        guard let (_, tab, source) = locate(surfaceView: surfaceView),
              tab.tree.isSplit,
              let node = tab.tree.node(of: source)
        else { return false }

        let focusDirection: SplitTree.FocusDirection
        switch direction {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: focusDirection = .previous
        case GHOSTTY_GOTO_SPLIT_NEXT:     focusDirection = .next
        case GHOSTTY_GOTO_SPLIT_UP:       focusDirection = .spatial(.up)
        case GHOSTTY_GOTO_SPLIT_DOWN:     focusDirection = .spatial(.down)
        case GHOSTTY_GOTO_SPLIT_LEFT:     focusDirection = .spatial(.left)
        case GHOSTTY_GOTO_SPLIT_RIGHT:    focusDirection = .spatial(.right)
        default: return false
        }

        guard let target = tab.tree.focusTarget(for: focusDirection, from: node) else {
            return false
        }

        // Leaving a zoomed pane unzooms unless we're just moving zoom focus —
        // kterm always unzooms on navigate (simpler than Ghostty's preference).
        if tab.tree.zoomed != nil {
            tab.tree = SplitTree(root: tab.tree.root, zoomed: nil)
        }
        focus(target, in: tab)
        return true
    }

    /// Ghostty `resize_split:*`.
    @discardableResult
    func resizeSplit(from surfaceView: SurfaceView, resize: ghostty_action_resize_split_s) -> Bool {
        guard let (_, tab, source) = locate(surfaceView: surfaceView),
              tab.tree.isSplit,
              let node = tab.tree.node(of: source)
        else { return false }

        let direction: SplitTree.Spatial.Direction
        switch resize.direction {
        case GHOSTTY_RESIZE_SPLIT_UP:    direction = .up
        case GHOSTTY_RESIZE_SPLIT_DOWN:  direction = .down
        case GHOSTTY_RESIZE_SPLIT_LEFT:  direction = .left
        case GHOSTTY_RESIZE_SPLIT_RIGHT: direction = .right
        default: return false
        }

        let bounds = CGRect(origin: .zero, size: tab.tree.viewBounds())
        do {
            tab.tree = try tab.tree.resizing(node: node, by: resize.amount, in: direction, with: bounds)
            return true
        } catch {
            return false
        }
    }

    /// Ghostty `equalize_splits` (also double-click on a divider).
    func equalizeSplits(from surfaceView: SurfaceView) {
        guard let (_, tab, _) = locate(surfaceView: surfaceView) else { return }
        equalizeSplits(in: tab)
    }

    func equalizeSplits(in tab: TerminalTab) {
        tab.tree = tab.tree.equalized()
    }

    /// Drag-divider resize of a specific split node.
    func resizeSplit(_ node: SplitTree.Node, to ratio: Double, in tab: TerminalTab) {
        let clamped = min(max(ratio, 0.1), 0.9)
        do {
            tab.tree = try tab.tree.replacing(node: node, with: node.resizing(to: clamped))
        } catch {
            NSLog("kterm: failed to resize split: \(error)")
        }
    }

    /// Ghostty `toggle_split_zoom`.
    @discardableResult
    func toggleSplitZoom(from surfaceView: SurfaceView) -> Bool {
        guard let (_, tab, source) = locate(surfaceView: surfaceView),
              tab.tree.isSplit,
              let node = tab.tree.node(of: source)
        else { return false }

        // Identify the zoomed pane by its leaf terminal, not enum/node
        // identity — safer across tree rebuilds.
        let isZoomedLeaf = tab.tree.zoomed.map {
            $0.leftmostLeaf() === source && $0.rightmostLeaf() === source
        } ?? false
        if isZoomedLeaf {
            tab.tree = SplitTree(root: tab.tree.root, zoomed: nil)
        } else {
            tab.tree = SplitTree(root: tab.tree.root, zoomed: node)
        }
        focus(source, in: tab)
        return true
    }

    /// Clear zoom on a tab (titlebar Reset Zoom button).
    func resetSplitZoom(in tab: TerminalTab) {
        guard tab.tree.zoomed != nil else { return }
        tab.tree = SplitTree(root: tab.tree.root, zoomed: nil)
    }

    /// Close a single pane (shell exited, or Ghostty `close_surface` / ⌘W).
    func close(_ term: Terminal, in tab: TerminalTab, group: TabGroup) {
        guard let node = tab.tree.node(of: term) else { return }

        // If this was the only pane, close the whole horizontal tab.
        if !tab.tree.isSplit {
            close(tab, in: group)
            return
        }

        // Pick a neighbour to focus after removal.
        let nextFocus: Terminal? = {
            if let n = tab.tree.focusTarget(for: .next, from: node), n !== term { return n }
            if let n = tab.tree.focusTarget(for: .previous, from: node), n !== term { return n }
            return nil
        }()

        tab.tree = tab.tree.removing(node)
        if let nextFocus {
            focus(nextFocus, in: tab)
        } else if let first = tab.focusedTerminal {
            focus(first, in: tab)
        }
    }

    /// Find the group/tab/terminal owning `surfaceView`.
    private func locate(surfaceView: SurfaceView) -> (TabGroup, TerminalTab, Terminal)? {
        for group in groups {
            for tab in group.tabs {
                if let term = tab.terminals.first(where: { $0.surfaceView === surfaceView }) {
                    return (group, tab, term)
                }
            }
        }
        return nil
    }

    private func makeTerminal(inheritFrom parent: Terminal? = nil,
                              inheritContext: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_TAB,
                              workingDirectory: String? = nil) -> Terminal {
        let term = Terminal(app: ghostty, inheritFrom: parent, inheritContext: inheritContext,
                            workingDirectory: workingDirectory)
        term.surfaceView.onTitleChange = { [weak term] title in
            term?.title = title
        }
        term.surfaceView.onPwdChange = { [weak self, weak term] pwd in
            term?.pwd = pwd
            if let term { self?.refreshBranch(for: term) }
        }
        term.surfaceView.onNotification = { [weak self, weak term] title, body in
            guard let self, let term else { return }
            self.notify(from: term, title: title, body: body)
        }
        // A terminal bell (BEL) becomes a system notification too, so the same
        // "task done / needs input" cue works whether a program uses the bell
        // or an explicit OSC 9/777 notification.
        term.surfaceView.onBell = { [weak self, weak term] in
            guard let self, let term else { return }
            self.notify(from: term, title: "🔔", body: term.displayTitle)
        }
        // A keystroke or click in the content area acknowledges the tab's
        // notification: the attention border and the unread marker (sidebar dot
        // / horizontal-tab 🔔) dismiss together (see `acknowledge`).
        term.surfaceView.onInteraction = { [weak self, weak term] in
            guard let self, let term else { return }
            self.acknowledge(term)
        }
        // Clicking into a pane updates which split is focused.
        term.surfaceView.onFocus = { [weak self, weak term] in
            guard let self, let term,
                  let (_, tab, _) = self.locate(surfaceView: term.surfaceView)
            else { return }
            tab.focusedTerminalID = term.id
        }
        term.surfaceView.onClose = { [weak self, weak term] in
            guard let self, let term else { return }
            // Find which tab holds it and close that pane.
            for group in self.groups {
                for tab in group.tabs where tab.contains(term) {
                    self.close(term, in: tab, group: group)
                    return
                }
            }
        }
        return term
    }

    /// Records `term` as unread and posts a system notification. Mirroring
    /// cmux, the unread state is *always* recorded — the tab marker (🔔 /
    /// sidebar dot) and, for the on-screen tab, the content-area attention
    /// border show even while kterm is frontmost and this tab is focused. Only
    /// the OS banner and the dock bounce are suppressed when the user is already
    /// looking at this exact tab (kterm frontmost AND this tab visible). The
    /// `terminalID` lets a tap on the notification focus this tab (see
    /// `focusTerminal(withID:)`).
    private func notify(from term: Terminal, title: String, body: String) {
        let isInSelectedTab = selectedGroup?.selectedTab?.contains(term) == true
        let isFocusedPane = selectedGroup?.selectedTab?.focusedTerminal?.id == term.id
        // Any pane in the on-screen tab that pings gets an attention border
        // (even a non-focused split sibling), plus an unread marker on the tab.
        // Both stay until acknowledged (see `acknowledge`).
        if isInSelectedTab { term.showAttention = true }
        term.hasUnread = true
        // Suppress only the external cues when the user is already looking at
        // this exact pane: no OS banner, no dock bounce.
        let isFocused = NSApp.isActive && isFocusedPane
        guard !isFocused else { return }
        NotificationManager.post(title: title, body: body, terminalID: term.id)
        // Bounce the dock icon when kterm isn't the active app, so a background
        // ping is noticeable (mirrors ghostty's `requestUserAttention`).
        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
            dockAttentionRequests += 1
        }
    }

    /// Acknowledge `term`'s notification: clear the content-area attention
    /// border and the tab's unread marker (🔔 / sidebar dot) together.
    /// Mirroring cmux, a notification is marked read when its tab is selected,
    /// when kterm returns to the foreground, or on direct content interaction —
    /// not only on a keystroke/click. The guard avoids redundant Observation
    /// invalidations when there's nothing to clear.
    private func acknowledge(_ term: Terminal) {
        guard term.showAttention || term.hasUnread else { return }
        term.showAttention = false
        term.hasUnread = false
    }

    /// Re-resolves `term`'s git branch + status from its current `pwd`, off
    /// the main thread. Guards against races (pwd changing again mid-lookup,
    /// or the terminal closing) by re-checking `pwd` before writing back.
    private func refreshBranch(for term: Terminal) {
        let pwd = term.pwd
        Task { @MainActor [weak term] in
            let git = await GitBranch.info(for: pwd)
            guard let term, term.pwd == pwd else { return }
            term.git = git
        }
    }

    /// Make the selected terminal's view first responder so typing goes to it.
    private func focusSelected() {
        guard let view = selectedGroup?.selectedTab?.focusedTerminal?.surfaceView else { return }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}

extension TerminalTab {
    func contains(_ term: Terminal) -> Bool {
        tree.contains(term)
    }
}
