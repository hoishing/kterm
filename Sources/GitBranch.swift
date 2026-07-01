import Foundation

/// Looks up the current git branch for a directory, off the main thread.
enum GitBranch {
    /// Returns the short branch name for `path`, or `nil` if `path` isn't
    /// inside a git repo, has no `git` binary available, or is in a
    /// detached-HEAD state (no branch to show).
    static func current(for path: String) async -> String? {
        guard !path.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path, "symbolic-ref", "--short", "-q", "HEAD"]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe() // discard "not a git repo" noise
            do {
                try process.run()
            } catch {
                return nil
            }
            process.waitUntilExit()
            // Non-zero covers "not a repo" and detached HEAD alike.
            guard process.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            guard let branch = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty
            else { return nil }
            return branch
        }.value
    }
}
