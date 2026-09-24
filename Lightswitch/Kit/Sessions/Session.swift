import Foundation

/// One Claude Code session, decoded from `~/.claude-notch/sessions/<id>.json`.
public struct Session: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var state: SessionState
    public var cwd: String
    public var pid: Int32
    public var tty: String
    public var termProgram: String
    /// Set when Claude has been waiting on the user for a while (`idle_prompt`).
    public var idle: Bool
    public var updatedAt: Date

    public init(id: String, state: SessionState, cwd: String, pid: Int32 = 0,
                tty: String = "", termProgram: String = "", idle: Bool = false,
                updatedAt: Date = Date()) {
        self.id = id
        self.state = state
        self.cwd = cwd
        self.pid = pid
        self.tty = tty
        self.termProgram = termProgram
        self.idle = idle
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id = "session_id"
        case state, cwd, pid, tty
        case termProgram = "term_program"
        case idle
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        // An unknown state (a newer script than app) degrades to idle rather
        // than dropping the session.
        let raw = try c.decodeIfPresent(String.self, forKey: .state) ?? "idle"
        state = SessionState(rawValue: raw) ?? .idle
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid) ?? 0
        tty = try c.decodeIfPresent(String.self, forKey: .tty) ?? ""
        termProgram = try c.decodeIfPresent(String.self, forKey: .termProgram) ?? ""
        idle = try c.decodeIfPresent(Bool.self, forKey: .idle) ?? false
        let seconds = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        updatedAt = Date(timeIntervalSince1970: seconds)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(state.rawValue, forKey: .state)
        try c.encode(cwd, forKey: .cwd)
        try c.encode(pid, forKey: .pid)
        try c.encode(tty, forKey: .tty)
        try c.encode(termProgram, forKey: .termProgram)
        try c.encode(idle, forKey: .idle)
        try c.encode(Int(updatedAt.timeIntervalSince1970), forKey: .updatedAt)
    }

    /// The last path component of the working directory: what the list shows.
    public var folderName: String {
        guard !cwd.isEmpty else { return "" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? cwd : name
    }

    /// The last four characters of the id, to tell two sessions in the same
    /// folder apart.
    public var shortID: String {
        String(id.suffix(4))
    }

    /// "now", "12s", "3m", "2h", "1d": the age shown in the list.
    public func age(at now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(updatedAt))
        switch s {
        case ..<5: return "now"
        case ..<60: return "\(Int(s))s"
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86400: return "\(Int(s / 3600))h"
        default: return "\(Int(s / 86400))d"
        }
    }
}
