import Foundation
import GhosttyKit

/// kterm's text configuration, read once at launch from `~/.config/kterm/config`.
///
/// The file uses libghostty's `key = value` syntax. Lines whose key starts with
/// `kterm-` configure the app shell (handled here) and are stripped before the
/// rest of the file is handed to libghostty, so any standard Ghostty setting
/// (font-family, font-size, theme, background, cursor-style, command, ...) works
/// unchanged.
struct KtermConfig {
    /// Where a newly created tab is inserted. `kterm-new-tab-position`.
    enum NewTabPosition: String {
        /// Append after all existing tabs.
        case end
        /// Insert right after the current tab, pushing later tabs back (default).
        case afterCurrent = "after-current"
    }

    /// Width of the vertical (sidebar) tab column, in points. `kterm-sidebar-width`.
    var sidebarWidth: CGFloat = 160

    /// Placement of new ⌘N/⌘T tabs. `kterm-new-tab-position`.
    var newTabPosition: NewTabPosition = .afterCurrent

    /// Programming ligatures. Off by default; `kterm-font-ligatures = true`
    /// re-enables them. Disabling maps to libghostty's `font-feature` (the
    /// `-calt, -liga, -dlig` idiom Ghostty documents for turning ligatures off).
    var fontLigatures: Bool = false

    /// Lines to pass through to libghostty verbatim.
    private var ghosttyLines: [String] = []

    /// Built-in libghostty defaults, applied before the user's config file so
    /// any matching key there overrides them (libghostty keeps the last value
    /// for scalar keys).
    private static let builtinDefaults = [
        "macos-option-as-alt = left",
    ]

    /// Ghostty `font-feature` line that turns programming ligatures off, per
    /// Ghostty's own docs. Appended (so it wins over any user `font-feature`)
    /// unless `kterm-font-ligatures = true`.
    private static let disableLigaturesLine = "font-feature = -calt, -liga, -dlig"

    static var path: URL {
        #if DEBUG
        // Let UI tests inject a throwaway config file (see `FontLigatureTests`).
        if let override = ProcessInfo.processInfo.environment["KTERM_UITEST_CONFIG"] {
            return URL(fileURLWithPath: override)
        }
        #endif
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/kterm/config")
    }

    static func load() -> KtermConfig {
        var config = KtermConfig()
        config.ghosttyLines = builtinDefaults

        if let text = try? String(contentsOf: path, encoding: .utf8) {
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }

                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                let key = parts.first ?? ""

                if key.hasPrefix("kterm-") {
                    let value = parts.count > 1 ? parts[1] : ""
                    config.apply(ktermKey: key, value: value)
                } else {
                    config.ghosttyLines.append(line)
                }
            }
        }

        if !config.fontLigatures {
            config.ghosttyLines.append(disableLigaturesLine)
        }
        return config
    }

    private mutating func apply(ktermKey key: String, value: String) {
        switch key {
        case "kterm-sidebar-width":
            if let w = Double(value), w > 0 { sidebarWidth = CGFloat(w) }
        case "kterm-new-tab-position":
            if let p = NewTabPosition(rawValue: value) { newTabPosition = p }
        case "kterm-font-ligatures":
            if let b = Self.parseBool(value) { fontLigatures = b }
        default:
            break // unknown kterm- key: ignore
        }
    }

    /// Parse a libghostty-style boolean (`true`/`false`, `yes`/`no`, `1`/`0`).
    private static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    /// Feed the passthrough settings to a libghostty config handle. libghostty
    /// only loads from files, so we materialize a temporary one.
    func applyToGhostty(_ cfg: ghostty_config_t?) {
        guard let cfg, !ghosttyLines.isEmpty else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kterm-ghostty-\(ProcessInfo.processInfo.processIdentifier).conf")
        let contents = ghosttyLines.joined(separator: "\n") + "\n"
        do {
            try contents.write(to: tmp, atomically: true, encoding: .utf8)
            tmp.path.withCString { ghostty_config_load_file(cfg, $0) }
        } catch {
            NSLog("kterm: failed to write temp ghostty config: \(error)")
        }
    }
}
