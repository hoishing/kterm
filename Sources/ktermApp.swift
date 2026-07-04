import SwiftUI
import UserNotifications

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
}

@main
struct KtermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let config: KtermConfig
    // One libghostty app for the whole process (ghostty_init runs once); every
    // window shares it. Per-window state lives in a fresh `AppModel` (see
    // `WindowRoot`).
    private let ghostty: GhosttyApp

    init() {
        let config = KtermConfig.load()
        self.config = config
        self.ghostty = GhosttyApp(config: config)
    }

    var body: some Scene {
        // A WindowGroup (not a single Window) so ⌘⇧N can open more windows.
        WindowGroup("kterm", id: "main") {
            WindowRoot(ghostty: ghostty, config: config)
        }
        // Hardcodes Ghostty's `macos-titlebar-style = tabs`: hide the system
        // titlebar so the tab strip (RootView) fills it edge to edge.
        .windowStyle(.hiddenTitleBar)
        .commands { KtermCommands() }
    }
}

/// One window's content: it owns that window's `AppModel`, created lazily on
/// first appearance so each window gets its own tabs while sharing the process
/// `GhosttyApp`.
private struct WindowRoot: View {
    let ghostty: GhosttyApp
    let config: KtermConfig
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
                )
            } else if let model {
                RootView(model: model, sidebarWidth: config.sidebarWidth)
                    // Make this window's model the target of the menu commands
                    // whenever it's the key window.
                    .focusedSceneValue(\.appModel, model)
            }
        }
        .onAppear {
            if model == nil, ghostty.app != nil {
                model = AppModel(ghostty: ghostty, newTabPosition: config.newTabPosition)
            }
        }
    }
}

/// kterm's menu commands. They target the key window's `AppModel` (via
/// `@FocusedValue`), so tab/sidebar shortcuts act on the front window.
private struct KtermCommands: Commands {
    @FocusedValue(\.appModel) private var model: AppModel?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Replace the default New Window (⌘N) with kterm's tab commands, plus
        // ⌘⇧N to open a new window.
        CommandGroup(replacing: .newItem) {
            Button("New Vertical Tab") { model?.newVerticalTab() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Horizontal Tab") { model?.newHorizontalTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        // Close the active tab with the standard ⌘W.
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(after: .newItem) {
            Button("Close Tab") { model?.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)

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
            Button("Previous Vertical Tab") { model?.selectPrevVerticalTab() }
                .keyboardShortcut("[", modifiers: [.command, .control])
            Button("Next Vertical Tab") { model?.selectNextVerticalTab() }
                .keyboardShortcut("]", modifiers: [.command, .control])
        }
        // ⌘` — cycle key focus through kterm's windows.
        CommandGroup(after: .windowList) {
            Button("Cycle Windows") { AppModel.cycleWindow() }
                .keyboardShortcut("`", modifiers: .command)
        }
    }
}
