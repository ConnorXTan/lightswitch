import Foundation

/// Sessions that work in the same repository: what the open notch lists as
/// one project with each Claude terminal under it. A session in a subfolder
/// or a linked worktree belongs to the repository above it.
public struct ProjectGroup: Identifiable, Equatable {
    /// The repository root, or the working directory when there is none.
    public let id: String
    /// The root's folder name, what the header shows.
    public let name: String
    /// Where the root lives, home abbreviated to `~`, to tell two projects
    /// with the same name apart.
    public let location: String
    public let sessions: [Session]

    public init(root: String, sessions: [Session]) {
        id = root
        let folder = (root as NSString).lastPathComponent
        name = folder.isEmpty ? "untitled" : folder
        let parent = (root as NSString).deletingLastPathComponent
        location = root.isEmpty ? "" : (parent as NSString).abbreviatingWithTildeInPath
        self.sessions = sessions
    }

    /// The state that matters most among the group's sessions.
    public var attention: SessionState {
        let order: [SessionState] = [.needsYou, .working, .done, .idle]
        return order.first { state in sessions.contains { $0.state == state } } ?? .idle
    }

    /// What sets a session apart inside its project: the path below the
    /// root, just the name for a Claude Code worktree, the folder name for a
    /// worktree kept elsewhere. Empty for a session at the root.
    public func subpath(of session: Session) -> String {
        let cwd = session.cwd
        if cwd.isEmpty || cwd == id { return "" }
        guard cwd.hasPrefix(id + "/") else { return session.folderName }
        var rel = String(cwd.dropFirst(id.count + 1))
        let worktrees = ".claude/worktrees/"
        if rel.hasPrefix(worktrees) { rel = String(rel.dropFirst(worktrees.count)) }
        return rel
    }

    /// Groups in order of each project's first session; sessions keep the
    /// order they were given. `root` maps a working directory to its
    /// repository (injected so tests need no file system).
    public static func grouping(_ sessions: [Session],
                                root: (String) -> String = ProjectRoot.resolve) -> [ProjectGroup] {
        var order: [String] = []
        var byRoot: [String: [Session]] = [:]
        for session in sessions {
            let r = root(session.cwd)
            if byRoot[r] == nil { order.append(r) }
            byRoot[r, default: []].append(session)
        }
        return order.map { ProjectGroup(root: $0, sessions: byRoot[$0]!) }
    }
}

public extension Session {
    /// "VS Code · ttys004": which terminal window this session lives in.
    var terminalLabel: String {
        let app = TerminalKind(termProgram: termProgram).displayName
        let where_ = tty.isEmpty ? shortID : tty
        return "\(app) · \(where_)"
    }

    /// The repository this session works in, by folder name; the working
    /// directory's own name when it is not in one. What the peek announces.
    var projectName: String {
        let name = (ProjectRoot.resolve(cwd) as NSString).lastPathComponent
        return name.isEmpty ? folderName : name
    }
}
