import SwiftUI

@main
struct KtermApp: App {
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
            }
        }
    }
}
