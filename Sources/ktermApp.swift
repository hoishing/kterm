import SwiftUI
import UserNotifications

/// Hardcodes Ghostty's `quit-after-last-window-closed = true`: terminate the
/// process once the (single) window closes instead of lingering in the dock.
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
}

@main
struct KtermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    private let config: KtermConfig

    init() {
        let config = KtermConfig.load()
        self.config = config
        let ghostty = GhosttyApp(config: config)
        _model = State(initialValue: AppModel(ghostty: ghostty))
    }

    var body: some Scene {
        Window("kterm", id: "main") {
            Group {
                if model.ghostty.app != nil {
                    RootView(model: model, sidebarWidth: config.sidebarWidth)
                } else {
                    ContentUnavailableView(
                        "libghostty failed to initialize",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Check Console.app for kterm logs.")
                    )
                }
            }
        }
        // Hardcodes Ghostty's `macos-titlebar-style = tabs`: hide the system
        // titlebar so the tab strip (RootView) fills it edge to edge.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Replace the default New Window (⌘N) with kterm's tab commands.
            CommandGroup(replacing: .newItem) {
                Button("New Vertical Tab") { model.newVerticalTab() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Horizontal Tab") { model.newHorizontalTab() }
                    .keyboardShortcut("t", modifiers: .command)
            }
            // Close the active tab with the standard ⌘W.
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(after: .newItem) {
                Button("Close Tab") { model.closeActiveTab() }
                    .keyboardShortcut("w", modifiers: .command)

                Divider()

                // ⌘B — toggle the vertical tab sidebar.
                Button(model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    model.sidebarVisible.toggle()
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                // ⌘1…⌘9 — jump to a vertical tab (group) by position.
                ForEach(1...9, id: \.self) { n in
                    Button("Select Vertical Tab \(n)") { model.selectGroup(at: n - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }

                Divider()

                // ⌘⇧[ / ⌘⇧] — previous/next horizontal tab (terminal).
                Button("Previous Horizontal Tab") { model.selectPrevHorizontalTab() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Next Horizontal Tab") { model.selectNextHorizontalTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])

                // ⌘⌃[ / ⌘⌃] — previous/next vertical tab (group).
                Button("Previous Vertical Tab") { model.selectPrevVerticalTab() }
                    .keyboardShortcut("[", modifiers: [.command, .control])
                Button("Next Vertical Tab") { model.selectNextVerticalTab() }
                    .keyboardShortcut("]", modifiers: [.command, .control])
            }
        }
    }
}
