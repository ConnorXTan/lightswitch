import AppKit
import Foundation

/// Which terminal a session's shell runs in, from `$TERM_PROGRAM`.
///
/// Cursor reports `vscode` too, so it is handled through the bundle-id list
/// rather than a case of its own.
public enum TerminalKind: Equatable, CaseIterable {
    case iTerm
    case appleTerminal
    case vscode
    case ghostty
    case kitty
    case wezterm
    case warp
    case hyper
    case alacritty
    case unknown

    public init(termProgram: String) {
        switch termProgram.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "iterm.app", "iterm2", "iterm": self = .iTerm
        case "apple_terminal", "terminal.app": self = .appleTerminal
        case "vscode": self = .vscode
        case "ghostty": self = .ghostty
        case "kitty": self = .kitty
        case "wezterm": self = .wezterm
        case "warpterminal", "warp": self = .warp
        case "hyper": self = .hyper
        case "alacritty": self = .alacritty
        default: self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .iTerm: return "iTerm"
        case .appleTerminal: return "Terminal"
        case .vscode: return "VS Code"
        case .ghostty: return "Ghostty"
        case .kitty: return "kitty"
        case .wezterm: return "WezTerm"
        case .warp: return "Warp"
        case .hyper: return "Hyper"
        case .alacritty: return "Alacritty"
        case .unknown: return "Terminal"
        }
    }

    /// Bundle identifiers to look for among running apps, most likely first.
    public var bundleIdentifiers: [String] {
        switch self {
        case .iTerm: return ["com.googlecode.iterm2"]
        case .appleTerminal: return ["com.apple.Terminal"]
        case .vscode:
            return [
                "com.microsoft.VSCode",
                "com.microsoft.VSCodeInsiders",
                "com.todesktop.230313mzl4w4u92", // Cursor
                "com.vscodium.codium",
            ]
        case .ghostty: return ["com.mitchellh.ghostty"]
        case .kitty: return ["net.kovidgoyal.kitty"]
        case .wezterm: return ["com.github.wez.wezterm"]
        case .warp: return ["dev.warp.Warp-Stable"]
        case .hyper: return ["co.zeit.hyper"]
        case .alacritty: return ["org.alacritty"]
        case .unknown: return []
        }
    }
}

/// Brings the terminal that owns a Claude Code session to the front.
///
/// iTerm and Terminal can select the exact tab by tty through AppleScript.
/// VS Code cannot be scripted that way, but opening the session's folder
/// with it brings forward the window that already has that folder open.
/// Everything else is simply activated.
public enum TerminalFocuser {
    public enum Result: Equatable {
        case focusedTab
        case activatedApp
        case openedFolder
        case notRunning
        case scriptFailed(String)
    }

    /// Normalises `ttys004` or `/dev/ttys004` to `/dev/ttys004`.
    public static func devicePath(for tty: String) -> String {
        let trimmed = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/dev/") ? trimmed : "/dev/" + trimmed
    }

    /// Wraps a value as an AppleScript string literal, escaping backslashes
    /// and quotes.
    static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    /// The AppleScript that selects the tab owning `tty`, or nil when the
    /// terminal cannot be scripted that way.
    public static func script(for kind: TerminalKind, tty: String) -> String? {
        let device = appleScriptLiteral(devicePath(for: tty))
        switch kind {
        case .iTerm:
            return """
            tell application "iTerm"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is \(device) then
                                select t
                                select s
                                set index of w to 1
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        case .appleTerminal:
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is \(device) then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }

    /// Focuses the terminal for a session. Never throws; the result says how
    /// far it got.
    @MainActor
    public static func focus(termProgram: String, tty: String, cwd: String) -> Result {
        let kind = TerminalKind(termProgram: termProgram)
        var scriptError: String?

        if let source = script(for: kind, tty: tty) {
            switch runAppleScript(source) {
            case .success(true):
                return .focusedTab
            case .success(false):
                scriptError = "no tab owns \(devicePath(for: tty))"
            case .failure(let message):
                scriptError = message
            }
        }

        guard let app = runningApp(for: kind, termProgram: termProgram) else {
            if let scriptError { return .scriptFailed(scriptError) }
            return .notRunning
        }

        if kind == .vscode, !cwd.isEmpty, let appURL = app.bundleURL {
            let folder = URL(fileURLWithPath: cwd, isDirectory: true)
            if FileManager.default.fileExists(atPath: folder.path) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open([folder], withApplicationAt: appURL,
                                        configuration: configuration) { _, _ in }
                return .openedFolder
            }
        }

        app.activate()
        return .activatedApp
    }

    // MARK: - Helpers

    private enum ScriptOutcome {
        case success(Bool)
        case failure(String)
    }

    @MainActor
    private static func runAppleScript(_ source: String) -> ScriptOutcome {
        guard let script = NSAppleScript(source: source) else {
            return .failure("could not compile AppleScript")
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed"
            return .failure(message)
        }
        return .success(descriptor.booleanValue)
    }

    @MainActor
    private static func runningApp(for kind: TerminalKind, termProgram: String) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications

        for identifier in kind.bundleIdentifiers {
            if let app = running.first(where: { $0.bundleIdentifier == identifier }) {
                return app
            }
        }

        guard kind == .unknown else { return nil }
        let needle = termProgram.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return running.first { app in
            (app.localizedName?.lowercased().contains(needle) ?? false)
                || (app.bundleIdentifier?.lowercased().contains(needle) ?? false)
        }
    }
}
