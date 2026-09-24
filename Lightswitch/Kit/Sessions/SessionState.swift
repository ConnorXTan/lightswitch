import Foundation

/// What a Claude Code session is doing, as written by the hook script.
public enum SessionState: String, Codable, CaseIterable, Equatable {
    case idle
    case working
    case needsYou = "needs_you"
    case done

    /// The word shown next to the dot in the open list.
    public var label: String {
        switch self {
        case .idle: return "idle"
        case .working: return "working"
        case .needsYou: return "needs you"
        case .done: return "done"
        }
    }

    /// A short spoken form for the alert peek and accessibility labels.
    public var announcement: String {
        switch self {
        case .idle: return "is idle"
        case .working: return "is working"
        case .needsYou: return "needs you"
        case .done: return "is done"
        }
    }
}
