import Foundation

/// Puts the hook script in `~/.claude/hooks/` and merges the hooks block into
/// `~/.claude/settings.json`, or takes both out again.
///
/// The settings file belongs to the user, so every write is conservative: the
/// existing file is validated before anything is touched, copied to
/// `settings.json.bak`, and only entries whose command mentions `notch.sh`
/// are ever added or removed. Everything else survives byte-for-byte in
/// meaning (the file is re-serialised pretty-printed with sorted keys).
public struct HookInstaller {
    public enum Status: Equatable {
        case installed
        case notInstalled
        /// Some pieces are present. `missing` names the absent hook events,
        /// and `"notch.sh"` when the script itself is missing.
        case partial(missing: [String])
        /// `settings.json` could not be parsed; the reason is human-readable.
        case invalidSettings(String)
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidSettings(String)

        public var errorDescription: String? {
            switch self {
            case .invalidSettings(let reason):
                return "~/.claude/settings.json is not valid JSON, so it was left alone: \(reason)"
            }
        }
    }

    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var claudeDirectory: URL { home.appendingPathComponent(".claude", isDirectory: true) }
    public var scriptURL: URL { claudeDirectory.appendingPathComponent("hooks/notch.sh") }
    public var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }
    public var backupURL: URL { claudeDirectory.appendingPathComponent("settings.json.bak") }
    public var sessionsDirectory: URL { home.appendingPathComponent(".claude-notch/sessions", isDirectory: true) }

    // MARK: Status

    public func status() -> Status {
        let scriptOK = FileManager.default.isExecutableFile(atPath: scriptURL.path)
        let settings: [String: Any]
        do {
            settings = try readSettings()
        } catch Error.invalidSettings(let reason) {
            return .invalidSettings(reason)
        } catch {
            return .invalidSettings(error.localizedDescription)
        }

        var missing = HookScript.events.filter { !Self.hasMarker(in: settings, event: $0) }
        if !scriptOK { missing.insert(HookScript.marker, at: 0) }

        if missing.isEmpty { return .installed }
        if !scriptOK, missing.count == HookScript.events.count + 1 { return .notInstalled }
        return .partial(missing: missing)
    }

    /// Where `jq` is, if anywhere. The script works without it; this is for
    /// showing the user which parser their hooks will use.
    public static func jqPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/jq" }
        candidates += ["/usr/bin/jq", "/opt/homebrew/bin/jq"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Install / uninstall

    public func install() throws {
        // Validate before touching anything, so a broken settings file never
        // ends up half-installed.
        let settings = try readSettings()
        try writeScript()
        try backupAndWrite(Self.merge(settings))
    }

    public func uninstall() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: settingsURL.path) {
            let settings = try readSettings()
            try backupAndWrite(Self.strip(settings))
        }
        if fm.fileExists(atPath: scriptURL.path) {
            try fm.removeItem(at: scriptURL)
        }
    }

    // MARK: Pure helpers

    /// Adds our entries to each event, unless that event already has one.
    public static func merge(_ settings: [String: Any]) -> [String: Any] {
        var out = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, ours) in HookScript.hooksBlock {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if !entries.contains(where: isOurs) {
                entries.append(contentsOf: ours as? [[String: Any]] ?? [])
            }
            hooks[event] = entries
        }
        out["hooks"] = hooks
        return out
    }

    /// Removes exactly our entries. Events and the `hooks` object itself are
    /// dropped only when removing ours emptied them.
    public static func strip(_ settings: [String: Any]) -> [String: Any] {
        var out = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return out }
        var changed = false
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.filter { !isOurs($0) }
            guard kept.count != entries.count else { continue }
            changed = true
            hooks[event] = kept.isEmpty ? nil : kept
        }
        guard changed else { return out }
        out["hooks"] = hooks.isEmpty ? nil : hooks
        return out
    }

    static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains(HookScript.marker) == true }
    }

    static func hasMarker(in settings: [String: Any], event: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any],
              let entries = hooks[event] as? [[String: Any]] else { return false }
        return entries.contains(where: isOurs)
    }

    // MARK: Files

    /// The parsed settings file, or an empty object when there is none.
    func readSettings() throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            throw Error.invalidSettings("could not read it: \(error.localizedDescription)")
        }
        if data.isEmpty { return [:] }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Error.invalidSettings(error.localizedDescription)
        }
        guard let dictionary = object as? [String: Any] else {
            throw Error.invalidSettings("the top level is not an object")
        }
        return dictionary
    }

    private func writeScript() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(HookScript.source.utf8).write(to: scriptURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    private func backupAndWrite(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            if fm.fileExists(atPath: backupURL.path) {
                try fm.removeItem(at: backupURL)
            }
            try fm.copyItem(at: settingsURL, to: backupURL)
        }
        var data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        try data.write(to: settingsURL, options: .atomic)
    }
}
