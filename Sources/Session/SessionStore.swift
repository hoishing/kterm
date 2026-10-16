import Foundation

/// Saved tab layout of every window, written on quit and restored on the next
/// launch (`kterm-restore-tabs`). Positions are indices, never `UUID`s, since
/// restored terminals get fresh ids.
struct Session: Codable {
    var windows: [WindowSnap]
}

struct WindowSnap: Codable {
    var groups: [GroupSnap]
    var selectedGroup: Int
    var sidebarVisible: Bool
}

struct GroupSnap: Codable {
    var tabs: [TabSnap]
    var selectedTab: Int
}

struct TabSnap: Codable {
    var root: NodeSnap
    /// Index of the focused pane in `SplitTree.terminals` order.
    var focusedPane: Int
}

indirect enum NodeSnap: Codable {
    /// `agent` is a `KtermAgent` raw value; the tab relaunches it with its
    /// continue flag.
    case leaf(pwd: String, agent: String?)
    case split(horizontal: Bool, ratio: Double, left: NodeSnap, right: NodeSnap)
}

enum SessionStore {
    /// The shared libghostty app, so quit-time saving reads the live
    /// `kterm-restore-tabs` (it follows config reloads).
    @MainActor static weak var ghostty: GhosttyApp?

    static var path: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("kterm/session.json")
    }

    static func load() -> Session? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func save(_ session: Session) {
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(session).write(to: path, options: .atomic)
        } catch {
            NSLog("kterm: failed to save session: \(error)")
        }
    }
}
