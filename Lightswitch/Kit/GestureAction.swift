import Foundation

/// What covering the notch does. Stored by raw value in Preferences.
public enum GestureAction: String, CaseIterable, Identifiable {
    /// Acknowledge the oldest session that needs you and jump to its terminal;
    /// with nothing red, open or close the notch.
    case smart
    case toggleNotch
    case acknowledge
    case playPause
    case closeWindow
    case none

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .smart: return "Jump to the session that needs you, else open the notch"
        case .toggleNotch: return "Open or close the notch"
        case .acknowledge: return "Acknowledge the session that needs you"
        case .playPause: return "Play or pause the music"
        case .closeWindow: return "Close the front window (⌘W)"
        case .none: return "Nothing"
        }
    }

    /// The lightswitch action spec run through the C engine, if any.
    public var actionSpec: String? {
        switch self {
        case .playPause: return "media:playpause"
        case .closeWindow: return "key:cmd+w"
        default: return nil
        }
    }

    /// Whether the action needs the Accessibility permission to post events.
    public var needsAccessibility: Bool { actionSpec != nil }
}
