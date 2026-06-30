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
    /// Width of the vertical (sidebar) tab column, in points. `kterm-sidebar-width`.
    var sidebarWidth: CGFloat = 160

    /// Lines to pass through to libghostty verbatim.
    private var ghosttyLines: [String] = []

    static var path: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/kterm/config")
    }

    static func load() -> KtermConfig {
        var config = KtermConfig()
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return config }

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
        return config
    }

    private mutating func apply(ktermKey key: String, value: String) {
        switch key {
        case "kterm-sidebar-width":
            if let w = Double(value), w > 0 { sidebarWidth = CGFloat(w) }
        default:
            break // unknown kterm- key: ignore
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
