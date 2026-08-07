import Foundation

/// Looks up the current git branch and a Starship-style compact status for a
/// directory, off the main thread.
///
/// Status symbols follow Starship's defaults (not the user's `starship.toml`):
/// `=` conflicted, `$` stashed, `✘` deleted, `»` renamed, `!` modified,
/// `+` staged, `?` untracked, then `⇕`/`⇡`/`⇣` for ahead/behind. Rendered as
/// `branch [symbols]` when any apply.
enum GitBranch {
    /// Branch name plus compact status symbols (no brackets).
    struct Info: Equatable, Sendable {
        let name: String
        /// Starship `$all_status$ahead_behind` body, e.g. `"!?"`, `"⇡"`, `""`.
        let status: String
    }

    /// Returns git info for `path`, or `nil` if `path` isn't inside a git repo,
    /// has no `git` binary available, or is in a detached-HEAD state.
    static func info(for path: String) async -> Info? {
        guard !path.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            guard let output = run(
                arguments: ["-C", path, "status", "--porcelain=v2", "--branch"]
            ), let parsed = parseStatus(output) else { return nil }

            let stashed = hasStash(at: path)
            let status = symbols(
                conflicted: parsed.conflicted,
                stashed: stashed,
                deleted: parsed.deleted,
                renamed: parsed.renamed,
                modified: parsed.modified,
                staged: parsed.staged,
                untracked: parsed.untracked,
                ahead: parsed.ahead,
                behind: parsed.behind
            )
            return Info(name: parsed.branch, status: status)
        }.value
    }

    // MARK: - git process

    /// Runs `/usr/bin/git` with `arguments`. Returns stdout on exit 0, else nil.
    private static func run(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe() // discard "not a git repo" noise
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// Whether `refs/stash` exists (Starship's stashed indicator).
    private static func hasStash(at path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "rev-parse", "--verify", "--quiet", "refs/stash"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - porcelain v2 parsing (mirrors Starship)

    private struct Parsed {
        var branch: String
        var ahead = 0
        var behind = 0
        var conflicted = 0
        var deleted = 0
        var renamed = 0
        var modified = 0
        var staged = 0
        var untracked = 0
    }

    private static func parseStatus(_ output: String) -> Parsed? {
        var branch: String?
        var ahead = 0
        var behind = 0
        var conflicted = 0
        var renamed = 0
        var untracked = 0
        var worktreeAdded = 0
        var worktreeDeleted = 0
        var worktreeModified = 0
        var indexAdded = 0
        var indexDeleted = 0
        var indexModified = 0
        var indexTypechanged = 0

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.hasPrefix("# branch.head ") {
                let name = String(line.dropFirst("# branch.head ".count))
                // Detached HEAD: no branch line to show (matches prior behavior).
                if name != "(detached)" { branch = name }
                continue
            }
            if line.hasPrefix("# branch.ab ") {
                // `# branch.ab +<ahead> -<behind>`
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    ahead = Int(parts[2].drop(while: { $0 == "+" })) ?? 0
                    behind = Int(parts[3].drop(while: { $0 == "-" })) ?? 0
                }
                continue
            }

            guard let kind = line.first else { continue }
            switch kind {
            case "1", "2":
                // `1 XY ...` / `2 XY ...` — XY are index/worktree status chars.
                guard line.count >= 4 else { continue }
                let xyStart = line.index(line.startIndex, offsetBy: 2)
                let xyEnd = line.index(xyStart, offsetBy: 2)
                let xy = line[xyStart..<xyEnd]
                let x = xy.first
                let y = xy.dropFirst().first
                if kind == "2" { renamed += 1 }
                if y == "A" { worktreeAdded += 1 }
                if y == "D" { worktreeDeleted += 1 }
                if y == "M" { worktreeModified += 1 }
                if x == "A" { indexAdded += 1 }
                if x == "D" { indexDeleted += 1 }
                if x == "M" { indexModified += 1 }
                if x == "T" { indexTypechanged += 1 }
            case "u":
                conflicted += 1
            case "?":
                untracked += 1
            default:
                break
            }
        }

        guard let branch else { return nil }

        // Starship aggregates:
        //   modified = worktree_modified + worktree_added
        //   staged   = index_modified + index_added + index_typechanged
        //   deleted  = worktree_deleted + index_deleted
        return Parsed(
            branch: branch,
            ahead: ahead,
            behind: behind,
            conflicted: conflicted,
            deleted: worktreeDeleted + indexDeleted,
            renamed: renamed,
            modified: worktreeModified + worktreeAdded,
            staged: indexModified + indexAdded + indexTypechanged,
            untracked: untracked
        )
    }

    /// Starship default order: conflicted stashed deleted renamed modified
    /// typechanged staged untracked, then ahead_behind.
    private static func symbols(
        conflicted: Int,
        stashed: Bool,
        deleted: Int,
        renamed: Int,
        modified: Int,
        staged: Int,
        untracked: Int,
        ahead: Int,
        behind: Int
    ) -> String {
        var s = ""
        if conflicted > 0 { s += "=" }
        if stashed { s += "$" }
        if deleted > 0 { s += "✘" }
        if renamed > 0 { s += "»" }
        if modified > 0 { s += "!" }
        // typechanged default symbol is empty — skip
        if staged > 0 { s += "+" }
        if untracked > 0 { s += "?" }
        if ahead > 0 && behind > 0 {
            s += "⇕"
        } else if ahead > 0 {
            s += "⇡"
        } else if behind > 0 {
            s += "⇣"
        }
        return s
    }
}
