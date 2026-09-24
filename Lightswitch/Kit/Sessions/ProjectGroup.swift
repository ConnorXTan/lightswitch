import Foundation

/// Sessions that share a working directory: what the open notch lists as
/// one project with each Claude terminal under it.
public struct ProjectGroup: Identifiable, Equatable {
    /// The working directory.
    public let id: String
    /// The folder name, what the header shows.
    public let name: String
    /// Where the folder lives, home abbreviated to `~`, to tell two projects
    /// with the same name apart.
    public let location: String
    public let sessions: [Session]

    public init(cwd: String, sessions: [Session]) {
        id = cwd
        let folder = sessions.first?.folderName ?? ""
        name = folder.isEmpty ? "untitled" : folder
        let parent = (cwd as NSString).deletingLastPathComponent
        location = cwd.isEmpty ? "" : (parent as NSString).abbreviatingWithTildeInPath
        self.sessions = sessions
    }

    /// The state that matters most among the group's sessions.
    public var attention: SessionState {
        let order: [SessionState] = [.needsYou, .working, .done, .idle]
        return order.first { state in sessions.contains { $0.state == state } } ?? .idle
    }

    /// Groups in order of each project's first session; sessions keep the
    /// order they were given.
    public static func grouping(_ sessions: [Session]) -> [ProjectGroup] {
        var order: [String] = []
        var byCwd: [String: [Session]] = [:]
        for session in sessions {
            if byCwd[session.cwd] == nil { order.append(session.cwd) }
            byCwd[session.cwd, default: []].append(session)
        }
        return order.map { ProjectGroup(cwd: $0, sessions: byCwd[$0]!) }
    }
}

public extension Session {
    /// "VS Code · ttys004": which terminal window this session lives in.
    var terminalLabel: String {
        let app = TerminalKind(termProgram: termProgram).displayName
        let where_ = tty.isEmpty ? shortID : tty
        return "\(app) · \(where_)"
    }
}
