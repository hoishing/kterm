import AppKit
import SwiftUI
import Observation
import GhosttyKit

/// Owns the single global `ghostty_app_t` and the runtime callbacks libghostty
/// needs. One instance is created at launch and lives for the whole process.
///
/// This is a deliberately slim re-implementation of the embedding glue that
/// Ghostty's own macOS app exposes through its `Ghostty` Swift package. We only
/// wire up what kterm needs: app lifecycle, the wakeup tick, clipboard, and
/// surface close/title callbacks.
@Observable
@MainActor
final class GhosttyApp {
    /// The libghostty app handle. `nil` only if initialization failed.
    /// `nonisolated(unsafe)`: C pointer, only ever touched on the main thread.
    private(set) nonisolated(unsafe) var app: ghostty_app_t?

    /// The loaded libghostty configuration handle, kept so surfaces can
    /// inherit from it. Replaced on config reload (see `GHOSTTY_ACTION_CONFIG_CHANGE`).
    /// `nonisolated(unsafe)`: C pointer, only ever touched on the main thread.
    private(set) nonisolated(unsafe) var config: ghostty_config_t?

    /// Replace the app-level config handle, freeing the old one. Called from
    /// the `GHOSTTY_ACTION_CONFIG_CHANGE` callback; libghostty already cloned
    /// the incoming config for the app, so we take ownership of our clone.
    func setConfig(_ cfg: ghostty_config_t?) {
        let old = config
        config = cfg
        if let old { ghostty_config_free(old) }
    }

    /// kterm's shell settings (sidebar width, tab placement, UI font, …).
    /// Replaced on `reloadConfig()`; views read it reactively.
    var ktermConfig: KtermConfig

    init(config: KtermConfig) {
        self.ktermConfig = config
        // Resolve chrome font and shell settings before any window body runs.
        applyShellSettings(config)
        // Point libghostty at our bundled resources (Contents/Resources/ghostty)
        // so it can inject shell integration into the shell. This is what makes
        // the shell emit OSC 7 (working directory) and title reports. Must be set
        // before ghostty_init.
        if let resources = Bundle.main.resourceURL?.appendingPathComponent("ghostty").path {
            setenv("GHOSTTY_RESOURCES_DIR", resources, 1)
        }

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

    /// The terminal background color from the loaded config, used to tint the
    /// titlebar area above the terminal so it reads as one continuous surface.
    /// Falls back to the system text-background color if unset.
    var backgroundColor: NSColor {
        guard let config else { return .textBackgroundColor }
        var color = ghostty_config_color_s()
        let key = "background"
        guard ghostty_config_get(config, &color, key, UInt(key.utf8.count)) else {
            return .textBackgroundColor
        }
        return NSColor(srgbRed: Double(color.r) / 255,
                       green: Double(color.g) / 255,
                       blue: Double(color.b) / 255,
                       alpha: 1)
    }

    /// Reload configuration from disk and propagate it to libghostty and the
    /// app shell. Mirrors Ghostty's `reload_config` action (⌘⇧,).
    ///
    /// libghostty clones the config for the app internally on
    /// `GHOSTTY_ACTION_CONFIG_CHANGE`, so we can free our copy after the call.
    /// `self.config` is replaced when that action fires (see `configChange`).
    func reloadConfig() {
        let kterm = KtermConfig.load()
        let cfg = ghostty_config_new()
        kterm.applyToGhostty(cfg)
        ghostty_config_finalize(cfg)

        if let app {
            ghostty_app_update_config(app, cfg)
        }
        // Free our temporary; libghostty already cloned it for the app.
        ghostty_config_free(cfg)

        // Apply shell settings immediately (font, tab placement, sidebar width).
        applyShellSettings(kterm)
    }

    /// Apply the kterm-only shell settings. Called on launch and reload.
    private func applyShellSettings(_ config: KtermConfig) {
        ktermConfig = config
        KtermUIFont.configure(family: config.uiFontFamily)
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
            DispatchQueue.main.async { view.setTitle(title) }
            return true

        case GHOSTTY_ACTION_PWD:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface),
                  let pwdPtr = action.action.pwd.pwd else { return false }
            let pwd = String(cString: pwdPtr)
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async { view.onPwdChange?(pwd) }
            return true

        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let n = action.action.desktop_notification
            let title = n.title.map { String(cString: $0) } ?? "kterm"
            let body = n.body.map { String(cString: $0) } ?? ""
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async { view.onNotification?(title, body) }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async { view.onBell?() }
            return true

        // libghostty's built-in ⌘⇧, keybind surfaces here as an app-targeted
        // reload. Handle it so the menu item and the keybind share one path.
        case GHOSTTY_ACTION_RELOAD_CONFIG:
            guard let appUd = ghostty_app_userdata(app) else { return false }
            let ghostty = Unmanaged<GhosttyApp>.fromOpaque(appUd).takeUnretainedValue()
            let soft = action.action.reload_config.soft
            DispatchQueue.main.async {
                if soft {
                    ghostty.applyShellSettings(KtermConfig.load())
                } else {
                    ghostty.reloadConfig()
                }
            }
            return true

        // libghostty clones the config for the app internally (see
        // performPreAction in embedded.zig); we mirror it into `self.config`
        // so `backgroundColor` and inherited-config surfaces see the update.
        case GHOSTTY_ACTION_CONFIG_CHANGE:
            guard let appUd = ghostty_app_userdata(app) else { return false }
            let ghostty = Unmanaged<GhosttyApp>.fromOpaque(appUd).takeUnretainedValue()
            let cloned = ghostty_config_clone(action.action.config_change.config)
            DispatchQueue.main.async {
                ghostty.setConfig(cloned)
            }
            return true

        case GHOSTTY_ACTION_NEW_TAB:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async {
                for model in AppModel.all {
                    if model.locate(surfaceView: view) != nil {
                        model.newHorizontalTab(from: view)
                        return
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_NEW_WINDOW:
            DispatchQueue.main.async { AppModel.openNewWindow?() }
            return true

        case GHOSTTY_ACTION_GOTO_TAB:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let tab = action.action.goto_tab
            for model in AppModel.all {
                if model.gotoTab(from: view, tab: tab) { return true }
            }
            return false

        case GHOSTTY_ACTION_CLOSE_TAB:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let mode = action.action.close_tab_mode
            DispatchQueue.main.async {
                for model in AppModel.all { model.closeTab(from: view, mode: mode) }
            }
            return true

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async {
                for model in AppModel.all { model.closeWindow(from: view) }
            }
            return true

        case GHOSTTY_ACTION_MOVE_TAB:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let amount = Int(action.action.move_tab.amount)
            for model in AppModel.all {
                if model.moveTab(from: view, amount: amount) { return true }
            }
            return false

        case GHOSTTY_ACTION_OPEN_CONFIG:
            DispatchQueue.main.async { GhosttyApp.openKtermConfig() }
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            return GhosttyApp.openURL(action.action.open_url)

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let shape = action.action.mouse_shape
            DispatchQueue.main.async { view.setCursorShape(shape) }
            return true

        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let visible = action.action.mouse_visibility == GHOSTTY_MOUSE_VISIBLE
            DispatchQueue.main.async { view.setCursorVisible(visible) }
            return true

        case GHOSTTY_ACTION_SET_TAB_TITLE:
            // Same payload as SET_TITLE. Tab chips already show the focused
            // pane's surface title, so apply it on that path.
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface),
                  let titlePtr = action.action.set_tab_title.title else { return false }
            let title = String(cString: titlePtr)
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async { view.setTitle(title) }
            return true

        case GHOSTTY_ACTION_TOGGLE_FULLSCREEN:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async { view.window?.toggleFullScreen(nil) }
            return true

        case GHOSTTY_ACTION_QUIT:
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true

        // Split actions are handled by the owning AppModel (see AppModel's
        // newSplit / gotoSplit / …). Menu items and remaining Ghostty
        // keybinds drive these (super+[ / super+] are unbound by default):
        //   super+d / super+shift+d → new_split
        //   super+alt+arrows        → goto_split directional
        //   super+ctrl+arrows       → resize_split
        //   super+ctrl+=            → equalize_splits
        case GHOSTTY_ACTION_NEW_SPLIT:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let direction = action.action.new_split
            DispatchQueue.main.async {
                for model in AppModel.all {
                    model.newSplit(from: view, direction: direction)
                }
            }
            return true

        case GHOSTTY_ACTION_GOTO_SPLIT:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let direction = action.action.goto_split
            // Must run synchronously so performable keybinds learn whether a
            // target exists (return false → key event is not consumed).
            for model in AppModel.all {
                if model.gotoSplit(from: view, direction: direction) { return true }
            }
            return false

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let resize = action.action.resize_split
            for model in AppModel.all {
                if model.resizeSplit(from: view, resize: resize) { return true }
            }
            return false

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async {
                for model in AppModel.all { model.equalizeSplits(from: view) }
            }
            return true

        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let ud = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(ud).takeUnretainedValue()
            for model in AppModel.all {
                if model.toggleSplitZoom(from: view) { return true }
            }
            return false

        default:
            return false
        }
    }

    /// Open `~/.config/kterm/config` in the default editor, creating an empty
    /// file if it doesn't exist yet. Ghostty `open_config`.
    private static func openKtermConfig() {
        let url = KtermConfig.path
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data().write(to: url, options: .withoutOverwriting)
        }
        NSWorkspace.shared.open(url)
    }

    /// Ghostty `open_url`. OSC 8 targets only open http(s)/mailto; other
    /// schemes and local files from terminal output are ignored so they
    /// cannot reach Launch Services. Matches Ghostty's UntrustedURL policy
    /// for the allow-list (confirm/deny UI is omitted).
    private static func openURL(_ v: ghostty_action_open_url_s) -> Bool {
        let raw: String
        if let ptr = v.url {
            raw = String(data: Data(bytes: ptr, count: Int(v.len)), encoding: .utf8) ?? ""
        } else {
            raw = ""
        }
        guard !raw.isEmpty else { return true }

        if v.kind == GHOSTTY_ACTION_OPEN_URL_KIND_OSC8 {
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased()
            else { return true }
            switch scheme {
            case "http", "https":
                guard let host = url.host, !host.isEmpty else { return true }
                NSWorkspace.shared.open(url)
            case "mailto":
                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      !components.path.isEmpty else { return true }
                NSWorkspace.shared.open(url)
            default:
                break
            }
            return true
        }

        let url: URL
        if let candidate = URL(string: raw), candidate.scheme != nil {
            url = candidate
        } else {
            url = URL(filePath: (raw as NSString).standardizingPath)
        }

        if v.kind == GHOSTTY_ACTION_OPEN_URL_KIND_TEXT {
            let editor = NSWorkspace.shared.urlForApplication(toOpen: url)
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
            if let editor {
                NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
                return true
            }
        }

        NSWorkspace.shared.open(url)
        return true
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
