import Foundation

/// Finds the repository a working directory belongs to, so a session in a
/// subfolder or a linked worktree lists under the project it works on rather
/// than under its own folder name.
public enum ProjectRoot {
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    /// The root of the git repository containing `cwd`, following a linked
    /// worktree back to its main worktree. `cwd` itself (with `.` and `..`
    /// folded) when no ancestor is a repository. The answer is cached per
    /// path: the list asks for it on every redraw.
    public static func resolve(_ cwd: String) -> String {
        guard !cwd.isEmpty else { return "" }
        lock.lock()
        let hit = cache[cwd]
        lock.unlock()
        if let hit { return hit }
        let root = lookup(cwd)
        lock.lock()
        cache[cwd] = root
        lock.unlock()
        return root
    }

    static func lookup(_ cwd: String) -> String {
        let start = normalize(cwd)
        var dir = start
        while true {
            let git = dir + (dir == "/" ? ".git" : "/.git")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: git, isDirectory: &isDir) {
                if isDir.boolValue { return dir }
                // A linked worktree keeps a file there; a submodule does too,
                // and a submodule is its own project.
                return mainWorktree(gitFile: git, in: dir) ?? dir
            }
            if dir == "/" { return start }
            dir = (dir as NSString).deletingLastPathComponent
            if dir.isEmpty { dir = "/" }
        }
    }

    /// A linked worktree's `.git` file says `gitdir: <repo>/.git/worktrees/<name>`,
    /// and that directory's `commondir` points back at the repository's `.git`.
    /// Older layouts without `commondir` are read from the path's shape.
    static func mainWorktree(gitFile: String, in dir: String) -> String? {
        guard let text = try? String(contentsOfFile: gitFile, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        var gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitdir.hasPrefix("/") { gitdir = dir + "/" + gitdir }
        gitdir = normalize(gitdir)

        var common: String
        if let rel = try? String(contentsOfFile: gitdir + "/commondir", encoding: .utf8) {
            let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
            common = trimmed.hasPrefix("/") ? trimmed : gitdir + "/" + trimmed
        } else if let range = gitdir.range(of: "/.git/worktrees/") {
            common = String(gitdir[..<range.lowerBound]) + "/.git"
        } else {
            return nil
        }
        common = normalize(common)
        guard (common as NSString).lastPathComponent == ".git" else { return nil }
        return (common as NSString).deletingLastPathComponent
    }

    /// Folds `.`, `..`, and repeated slashes without touching symlinks, so
    /// paths compare as the hook wrote them.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }
}
