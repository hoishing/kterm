import AppKit
import GhosttyKit

/// Owns the single global `ghostty_app_t` and the runtime callbacks libghostty
/// needs. One instance is created at launch and lives for the whole process.
///
/// This is a deliberately slim re-implementation of the embedding glue that
/// Ghostty's own macOS app exposes through its `Ghostty` Swift package. We only
/// wire up what kterm needs: app lifecycle, the wakeup tick, clipboard, and
/// surface close/title callbacks.
@MainActor
final class GhosttyApp {
    /// The libghostty app handle. `nil` only if initialization failed.
    private(set) var app: ghostty_app_t?

    /// The loaded configuration handle, kept so surfaces can inherit from it.
    private(set) var config: ghostty_config_t?

    init(config: KtermConfig) {
        // ghostty_init must be called exactly once per process before anything
        // else. It consumes the process argv.
        let argv = CommandLine.unsafeArgv
        if ghostty_init(UInt(CommandLine.argc), argv) != GHOSTTY_SUCCESS {
            NSLog("kterm: ghostty_init failed")
            return
        }

        // Build the ghostty config from kterm's config file (passthrough keys).
        let cfg = ghostty_config_new()
        config.applyToGhostty(cfg)
        ghostty_config_finalize(cfg)
        self.config = cfg

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { ud in GhosttyApp.wakeup(ud) },
            action_cb: { app, target, action in GhosttyApp.action(app, target, action) },
            read_clipboard_cb: { ud, loc, state in GhosttyApp.readClipboard(ud, loc, state) },
            confirm_read_clipboard_cb: { _, _, _, _ in },
            write_clipboard_cb: { ud, loc, content, len, confirm in
                GhosttyApp.writeClipboard(ud, loc, content, len, confirm) },
            close_surface_cb: { ud, alive in GhosttyApp.closeSurface(ud, alive) }
        )

        guard let app = ghostty_app_new(&runtime, cfg) else {
            NSLog("kterm: ghostty_app_new failed")
            return
        }
        self.app = app

        // Track app focus so libghostty knows when we're frontmost.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appDidBecomeActive),
                           name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidResignActive),
                           name: NSApplication.didResignActiveNotification, object: nil)
    }

    deinit {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
    }

    /// Pump libghostty. Safe to call any time on the main thread.
    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    @objc private func appDidBecomeActive() {
        if let app { ghostty_app_set_focus(app, true) }
    }

    @objc private func appDidResignActive() {
        if let app { ghostty_app_set_focus(app, false) }
    }

    // MARK: - C callbacks

    /// libghostty wants a tick. Called from arbitrary threads, so bounce to main.
    private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async { app.tick() }
    }

    /// Resolve a SurfaceView from a surface-scoped userdata pointer.
    private static func surfaceView(_ userdata: UnsafeMutableRawPointer?) -> SurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    /// App-level action dispatch. We only care about a few; everything else is
    /// reported as unhandled (false) so libghostty keeps its default behavior.
    private static func action(
        _ app: ghostty_app_t?,
        _ target: ghostty_target_s,
        _ action: ghostty_action_s
    ) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface),
                  let titlePtr = action.action.set_title.title else { return false }
            let title = String(cString: titlePtr)
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async { view.onTitleChange?(title) }
            return true

        default:
            return false
        }
    }

    /// Shell exited (or surface asked to close). Tell the owner to drop the tab.
    private static func closeSurface(_ userdata: UnsafeMutableRawPointer?, _ processAlive: Bool) {
        guard let view = surfaceView(userdata) else { return }
        DispatchQueue.main.async { view.onClose?() }
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        _ location: ghostty_clipboard_e,
        _ state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let view = surfaceView(userdata), let surface = view.surface else { return false }
        guard let str = NSPasteboard.general.string(forType: .string) else { return false }
        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
        return true
    }

    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        _ location: ghostty_clipboard_e,
        _ content: UnsafePointer<ghostty_clipboard_content_s>?,
        _ len: Int,
        _ confirm: Bool
    ) {
        guard let content, len > 0 else { return }
        // Use the first text entry.
        for i in 0..<len {
            let item = content[i]
            guard let dataPtr = item.data else { continue }
            let str = String(cString: dataPtr)
            let pb = NSPasteboard.general
            pb.declareTypes([.string], owner: nil)
            pb.setString(str, forType: .string)
            return
        }
    }
}
