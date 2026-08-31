import SwiftUI
import UserNotifications
import GhosttyKit

/// Hardcodes Ghostty's `quit-after-last-window-closed = true`: terminate the
/// process once the last window closes instead of lingering in the dock.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force dark mode regardless of the system appearance.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        UNUserNotificationCenter.current().delegate = self
        NotificationManager.requestAuthorizationIfNeeded()
    }

    // Bell / OSC 9 / OSC 777 notifications are only posted when kterm isn't
    // already showing that tab (see AppModel's `onNotification` wiring), so
    // always present them once posted.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Tapping a notification brings kterm forward and focuses the tab that
    // raised it — its id was stashed in `userInfo` by `NotificationManager`.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let idString = response.notification.request.content.userInfo["terminalID"] as? String,
           let id = UUID(uuidString: idString) {
            Task { @MainActor in AppModel.focusTerminalAnyWindow(withID: id) }
        }
        completionHandler()
    }

    // Handles the URLs/files kterm is asked to open:
    //   * `kterm://focus-tab?id=<uuid>` raises the tab with that id — the same
    //     routing a notification tap uses (both go through `AppModel.focusTerminal`).
    //     A program in a tab finds its own id in the `KTERM_TAB_ID` env var.
    //   * a folder (e.g. `open -a kterm <dir>`, or Finder "Open With" / a folder
    //     dropped on the app icon) opens as a new tab whose shell starts there.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "kterm", url.host == "focus-tab" {
                guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      let idString = items.first(where: { $0.name == "id" })?.value,
                      let id = UUID(uuidString: idString) else { continue }
                Task { @MainActor in AppModel.focusTerminalAnyWindow(withID: id) }
                continue
            }
            // Only directories make sense as a terminal cwd; ignore plain files.
            var isDir: ObjCBool = false
            guard url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let path = url.path
            Task { @MainActor in AppModel.openDirectory(path) }
        }
    }
}

/// Exposes the key window's `AppModel` to the menu commands. Published per
/// window via `.focusedSceneValue`, so ⌘N/⌘T/… act on the front window.
extension FocusedValues {
    var appModel: AppModel? {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }

    private struct AppModelKey: FocusedValueKey { typealias Value = AppModel }

    /// The shared libghostty app, exposed so the app menu can reload config
    /// regardless of which window is key.
    var ghostty: GhosttyApp? {
        get { self[GhosttyKey.self] }
        set { self[GhosttyKey.self] = newValue }
    }

    private struct GhosttyKey: FocusedValueKey { typealias Value = GhosttyApp }
}

@main
struct KtermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// The shared libghostty app. Created once at launch; every window
    /// reads shell settings from `ghostty.ktermConfig` reactively.
    private let ghostty: GhosttyApp

    init() {
        let ghostty = GhosttyApp(config: KtermConfig.load())
        self.ghostty = ghostty
    }

    var body: some Scene {
        // A WindowGroup (not a single Window) so ⌘⇧N can open more windows.
        WindowGroup("kterm", id: "main") {
            WindowRoot(ghostty: ghostty)
        }
        // Hardcodes Ghostty's `macos-titlebar-style = tabs`: hide the system
        // titlebar so the tab strip (RootView) fills it edge to edge.
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .commands { KtermCommands() }
    }
}

/// One window's content: it owns that window's `AppModel`, created lazily on
/// first appearance so each window gets its own tabs while sharing the process
/// `GhosttyApp`.
private struct WindowRoot: View {
    let ghostty: GhosttyApp
    @State private var model: AppModel?

    var body: some View {
        ZStack {
            // A backing color so a new window doesn't flash white before its
            // model (and terminal) exist.
            Color(nsColor: ghostty.app != nil ? ghostty.backgroundColor : .windowBackgroundColor)
                .ignoresSafeArea()

            if ghostty.app == nil {
                ContentUnavailableView(
                    "libghostty failed to initialize",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Check Console.app for kterm logs.")
                        .font(KtermUIFont.font(size: 13))
                )
                .font(KtermUIFont.font(size: 15))
            } else if let model {
                RootView(model: model)
                    // Make this window's model the target of the menu commands
                    // whenever it's the key window.
                    .focusedSceneValue(\.appModel, model)
                    // Default chrome font; explicit sizes still go through
                    // `KtermUIFont` where they pin a point size.
                    .font(KtermUIFont.font(size: 13))
            }
        }
        .focusedSceneValue(\.ghostty, ghostty)
        .onAppear {
            if model == nil, ghostty.app != nil {
                model = AppModel(ghostty: ghostty)
            }
        }
    }
}

/// kterm's menu commands. They target the key window's `AppModel` (via
/// `@FocusedValue`), so tab/sidebar/split shortcuts act on the front window.
private struct KtermCommands: Commands {
    @FocusedValue(\.appModel) private var model: AppModel?
    @FocusedValue(\.ghostty) private var ghostty: GhosttyApp?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Hand `AppModel` a way to open a window on a cold `open -a kterm <dir>`
        // (the WindowGroup won't auto-open one — see `handlesExternalEvents`).
        // The commands/menu are built at launch even before any window exists,
        // so this closure is available when the folder-open arrives.
        let openWindow = openWindow
        let _ = (AppModel.openNewWindow = { openWindow(id: "main") })

        // Replace the default New Window (⌘N) so ⌘N is a vertical tab.
        // New Window itself is restored as ⌘⇧N (WindowGroup id "main").
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Vertical Tab") { model?.newVerticalTab() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Horizontal Tab") { model?.newHorizontalTab() }
                .keyboardShortcut("t", modifiers: .command)
        }

        // Ghostty's Reload Configuration (⌘⇧,). libghostty's built-in keybind
        // reaches the same handler via GHOSTTY_ACTION_RELOAD_CONFIG; the menu
        // item claims the key so the menu bar shows it.
        CommandGroup(replacing: .appSettings) {
            Button("Reload Configuration") { ghostty?.reloadConfig() }
                .keyboardShortcut(",", modifiers: [.command, .shift])
        }

        // ⌘W matches Ghostty's `close_surface`: close the focused pane (and the
        // tab only when it was the last pane). The tab-chip × still closes the
        // whole horizontal tab.
        CommandGroup(replacing: .saveItem) {}
        // Ghostty's ⌘Z / ⌘⇧Z (undo/redo) are unbound by default; drop the
        // system Edit-menu shortcuts so those keys reach the terminal.
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(after: .newItem) {
            Button("Close Surface") { model?.closeFocusedSurface() }
                .keyboardShortcut("w", modifiers: .command)

            Divider()

            // Pane splits — same labels/shortcuts as Ghostty's File menu.
            // Menu shortcuts intercept the keys before libghostty; the handlers
            // call the same AppModel paths Ghostty actions use.
            Button("Split Right") { model?.newSplit(GHOSTTY_SPLIT_DIRECTION_RIGHT) }
                .keyboardShortcut("d", modifiers: .command)
            Button("Split Left") { model?.newSplit(GHOSTTY_SPLIT_DIRECTION_LEFT) }
            Button("Split Down") { model?.newSplit(GHOSTTY_SPLIT_DIRECTION_DOWN) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Split Up") { model?.newSplit(GHOSTTY_SPLIT_DIRECTION_UP) }

            Divider()

            // ⌘B — toggle the vertical tab sidebar.
            Button((model?.sidebarVisible ?? true) ? "Hide Sidebar" : "Show Sidebar") {
                model?.sidebarVisible.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)

            Divider()

            // ⌘1…⌘9 — jump to a vertical tab (group) by position.
            ForEach(1...9, id: \.self) { n in
                Button("Select Vertical Tab \(n)") { model?.selectGroup(at: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }

            Divider()

            // ⌘⇧[ / ⌘⇧] — previous/next horizontal tab (terminal).
            Button("Previous Horizontal Tab") { model?.selectPrevHorizontalTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Next Horizontal Tab") { model?.selectNextHorizontalTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])

            // ⌘⌃[ / ⌘⌃] — previous/next vertical tab (group).
            // ⌘` is left unbound so macOS Cycle Windows works.
            Button("Previous Vertical Tab") { model?.selectPrevVerticalTab() }
                .keyboardShortcut("[", modifiers: [.command, .control])
            Button("Next Vertical Tab") { model?.selectNextVerticalTab() }
                .keyboardShortcut("]", modifiers: [.command, .control])
        }

        // Pane navigation / zoom / resize — same labels as Ghostty's Window menu.
        CommandGroup(after: .windowList) {
            Button("Zoom Split") { model?.toggleSplitZoom() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])

            Button("Select Previous Split") { model?.gotoSplit(GHOSTTY_GOTO_SPLIT_PREVIOUS) }
            Button("Select Next Split") { model?.gotoSplit(GHOSTTY_GOTO_SPLIT_NEXT) }

            Menu("Select Split") {
                Button("Select Split Above") { model?.gotoSplit(GHOSTTY_GOTO_SPLIT_UP) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Select Split Below") { model?.gotoSplit(GHOSTTY_GOTO_SPLIT_DOWN) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Button("Select Split Left") { model?.gotoSplit(GHOSTTY_GOTO_SPLIT_LEFT) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Select Split Right") { model?.gotoSplit(GHOSTTY_GOTO_SPLIT_RIGHT) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }

            Menu("Resize Split") {
                Button("Equalize Splits") { model?.equalizeSplits() }
                    .keyboardShortcut("=", modifiers: [.command, .control])
                Button("Move Divider Up") { model?.resizeSplit(direction: GHOSTTY_RESIZE_SPLIT_UP) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .control])
                Button("Move Divider Down") { model?.resizeSplit(direction: GHOSTTY_RESIZE_SPLIT_DOWN) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .control])
                Button("Move Divider Left") { model?.resizeSplit(direction: GHOSTTY_RESIZE_SPLIT_LEFT) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                Button("Move Divider Right") { model?.resizeSplit(direction: GHOSTTY_RESIZE_SPLIT_RIGHT) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
            }
        }
    }
}
