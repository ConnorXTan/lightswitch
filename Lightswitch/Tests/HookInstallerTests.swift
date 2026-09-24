import XCTest
@testable import LightswitchKit

final class HookInstallerTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HookInstallerTests.swift
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // Lightswitch
    private static let scriptFile = repoRoot.appendingPathComponent("hooks/notch.sh")

    private var home: URL!
    private var installer: HookInstaller!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("HookInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        installer = HookInstaller(home: home)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Script parity

    func testScriptSourceMatchesCanonicalFile() throws {
        let file = try String(contentsOf: Self.scriptFile, encoding: .utf8)
        XCTAssertEqual(HookScript.source, file, "hooks/notch.sh and HookScript.source have drifted")
    }

    func testCanonicalScriptIsExecutable() {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Self.scriptFile.path))
    }

    // MARK: - merge / strip

    func testMergeIntoEmptySettingsAddsEveryEvent() {
        let merged = HookInstaller.merge([:])
        let hooks = merged["hooks"] as? [String: Any]
        XCTAssertEqual(Set(hooks?.keys.map { $0 } ?? []), Set(HookScript.events))
        for event in HookScript.events {
            XCTAssertTrue(HookInstaller.hasMarker(in: merged, event: event), event)
        }

        let notification = hooks?["Notification"] as? [[String: Any]]
        XCTAssertEqual(notification?.count, 3)
        XCTAssertEqual(notification?.map { $0["matcher"] as? String },
                       ["permission_prompt", "elicitation_dialog", "idle_prompt"])

        let start = (hooks?["SessionStart"] as? [[String: Any]])?.first
        XCTAssertEqual(start?["matcher"] as? String, "startup|resume|clear|fork")
        let startHook = (start?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(startHook?["command"] as? String, "~/.claude/hooks/notch.sh idle")
        XCTAssertEqual(startHook?["async"] as? Bool, true)
        XCTAssertEqual(startHook?["timeout"] as? Int, 5)
        XCTAssertEqual(startHook?["type"] as? String, "command")

        let prompt = (hooks?["UserPromptSubmit"] as? [[String: Any]])?.first
        XCTAssertNil(prompt?["matcher"])

        let end = ((hooks?["SessionEnd"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        XCTAssertNil(end?["async"], "SessionEnd must run synchronously")
        XCTAssertEqual(end?["timeout"] as? Int, 2)
        XCTAssertEqual(end?["command"] as? String, "~/.claude/hooks/notch.sh gone")
    }

    private var unrelatedSettings: [String: Any] {
        [
            "permissions": ["allow": ["Bash(ls)"]],
            "env": ["FOO": "bar"],
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "say done"]]]],
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "audit.sh"]]]],
            ],
        ]
    }

    func testMergeKeepsUnrelatedHooksAndKeys() {
        let merged = HookInstaller.merge(unrelatedSettings)
        XCTAssertEqual((merged["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(ls)"])
        XCTAssertEqual(merged["env"] as? [String: String], ["FOO": "bar"])

        let hooks = merged["hooks"] as! [String: Any]
        let stop = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2)
        XCTAssertEqual((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String, "say done")
        XCTAssertTrue(HookInstaller.isOurs(stop[1]))

        let pre = hooks["PreToolUse"] as! [[String: Any]]
        XCTAssertEqual(pre.count, 1)
        XCTAssertEqual(pre[0]["matcher"] as? String, "Bash")
    }

    func testMergeIsIdempotent() {
        let once = HookInstaller.merge(unrelatedSettings)
        let twice = HookInstaller.merge(once)
        XCTAssertEqual(NSDictionary(dictionary: once), NSDictionary(dictionary: twice))
    }

    func testStripRemovesOnlyOurEntries() {
        let stripped = HookInstaller.strip(HookInstaller.merge(unrelatedSettings))
        XCTAssertEqual(NSDictionary(dictionary: stripped), NSDictionary(dictionary: unrelatedSettings))
    }

    func testStripLeavesSettingsWithoutOurEntriesUntouched() {
        XCTAssertEqual(NSDictionary(dictionary: HookInstaller.strip(unrelatedSettings)),
                       NSDictionary(dictionary: unrelatedSettings))
        let noHooks: [String: Any] = ["env": ["A": "1"]]
        XCTAssertEqual(NSDictionary(dictionary: HookInstaller.strip(noHooks)), NSDictionary(dictionary: noHooks))
    }

    func testStripDropsHooksObjectOnlyWhenWeEmptiedIt() {
        let stripped = HookInstaller.strip(HookInstaller.merge([:]))
        XCTAssertNil(stripped["hooks"])
    }

    // MARK: - install / uninstall on disk

    private func write(settings text: String) throws {
        try FileManager.default.createDirectory(at: installer.claudeDirectory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: installer.settingsURL)
    }

    private func readSettings() throws -> [String: Any] {
        let data = try Data(contentsOf: installer.settingsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInstallThenUninstallRoundTrip() throws {
        let original = #"{"permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try write(settings: original)
        XCTAssertEqual(installer.status(), .notInstalled)

        try installer.install()

        XCTAssertEqual(installer.status(), .installed)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installer.scriptURL.path))
        XCTAssertEqual(try String(contentsOf: installer.scriptURL, encoding: .utf8), HookScript.source)
        XCTAssertEqual(try String(contentsOf: installer.backupURL, encoding: .utf8), original)

        var settings = try readSettings()
        XCTAssertEqual((settings["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(ls)"])
        var stop = (settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2)
        let text = try String(contentsOf: installer.settingsURL, encoding: .utf8)
        XCTAssertFalse(text.contains("\\/"), "slashes must not be escaped")
        XCTAssertTrue(text.contains("~/.claude/hooks/notch.sh idle"))

        // Installing again changes nothing.
        try installer.install()
        settings = try readSettings()
        stop = (settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2)
        for event in HookScript.events {
            let entries = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]]
            let ours = (HookScript.hooksBlock[event] as? [[String: Any]])?.count
            XCTAssertEqual(entries?.filter(HookInstaller.isOurs).count, ours, event)
        }

        try installer.uninstall()

        XCTAssertEqual(installer.status(), .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptURL.path))
        settings = try readSettings()
        XCTAssertEqual((settings["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(ls)"])
        stop = (settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1)
        XCTAssertEqual((stop?[0]["hooks"] as? [[String: Any]])?[0]["command"] as? String, "say done")
        XCTAssertEqual(Set(((settings["hooks"] as? [String: Any]) ?? [:]).keys), ["Stop"])
    }

    func testInstallWithoutASettingsFileCreatesOne() throws {
        XCTAssertEqual(installer.status(), .notInstalled)
        try installer.install()
        XCTAssertEqual(installer.status(), .installed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.backupURL.path),
                       "nothing to back up")
        let settings = try readSettings()
        XCTAssertEqual(Set(((settings["hooks"] as? [String: Any]) ?? [:]).keys), Set(HookScript.events))
    }

    func testInvalidSettingsAreRefusedAndLeftAlone() throws {
        let broken = "{ this is not json"
        try write(settings: broken)

        XCTAssertThrowsError(try installer.install()) { error in
            guard case HookInstaller.Error.invalidSettings = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: installer.settingsURL, encoding: .utf8), broken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.backupURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptURL.path))
        if case .invalidSettings = installer.status() {} else {
            XCTFail("status should report the invalid file, got \(installer.status())")
        }
        XCTAssertThrowsError(try installer.uninstall())
        XCTAssertEqual(try String(contentsOf: installer.settingsURL, encoding: .utf8), broken)
    }

    func testPartialStatusNamesWhatIsMissing() throws {
        var settings = HookInstaller.merge([:])
        var hooks = settings["hooks"] as! [String: Any]
        hooks["SessionStart"] = nil
        hooks["Stop"] = nil
        settings["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: settings)
        try FileManager.default.createDirectory(at: installer.claudeDirectory, withIntermediateDirectories: true)
        try data.write(to: installer.settingsURL)

        XCTAssertEqual(installer.status(), .partial(missing: ["notch.sh", "SessionStart", "Stop"]))

        try installer.install()
        XCTAssertEqual(installer.status(), .installed)
    }

    func testJqPathFindsSystemJqAndHonoursPath() {
        XCTAssertEqual(HookInstaller.jqPath(environment: ["PATH": "/nonexistent"]), "/usr/bin/jq")
        XCTAssertEqual(HookInstaller.jqPath(environment: ["PATH": "/usr/bin:/bin"]), "/usr/bin/jq")
    }

    // MARK: - The script itself

    private struct Run {
        var status: Int32
        var stdout: String
    }

    @discardableResult
    private func runScript(_ state: String, payload: String?, home: URL, noJQ: Bool,
                           extraEnvironment: [String: String] = [:]) throws -> Run {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.scriptFile.path, state]
        var env = [
            "HOME": home.path,
            "PATH": "/usr/bin:/bin",
            "TERM_PROGRAM": "TestTerm",
        ]
        if noJQ { env["NOTCH_NO_JQ"] = "1" }
        env.merge(extraEnvironment) { $1 }
        process.environment = env

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        if let payload {
            input.fileHandleForWriting.write(Data(payload.utf8))
        }
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, stdout: String(decoding: out, as: UTF8.self))
    }

    private func sessionFile(_ id: String, home: URL) -> URL {
        home.appendingPathComponent(".claude-notch/sessions/\(id).json")
    }

    private func readSession(_ id: String, home: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: sessionFile(id, home: home))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func modificationDate(_ url: URL) throws -> Date {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }

    func testScriptReadsTheSessionNameFromTheTranscriptWithJq() throws {
        try XCTSkipIf(HookInstaller.jqPath() == nil, "jq is not installed on this machine")
        try sessionName(noJQ: false)
    }

    func testScriptReadsTheSessionNameFromTheTranscriptWithoutJq() throws {
        try sessionName(noJQ: true)
    }

    /// The name lives in the transcript Claude Code points the hook at: the
    /// last `custom-title` (from /rename) wins, an empty one clears it, and
    /// the generated `ai-title` is the fallback. A new name must defeat the
    /// unchanged-state skip.
    private func sessionName(noJQ: Bool) throws {
        let home = self.home.appendingPathComponent(noJQ ? "name-plutil" : "name-jq", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let transcript = home.appendingPathComponent("t1.jsonl")
        func append(_ line: String) throws {
            let handle = try FileHandle(forWritingTo: transcript)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
        }
        try #"""
        {"type":"user","message":{"role":"user","content":"hello"},"uuid":"u1","sessionId":"t1"}
        {"type":"ai-title","aiTitle":"Fix the notch \"margins\"","sessionId":"t1"}

        """#.write(to: transcript, atomically: true, encoding: .utf8)
        let payload = #"{"session_id":"t1","cwd":"/tmp/proj","transcript_path":"\#(transcript.path)"}"#

        try runScript("working", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(try readSession("t1", home: home)["title"] as? String, "Fix the notch \"margins\"")

        try append(#"{"type":"custom-title","customTitle":"Notch polish","sessionId":"t1"}"#)
        try runScript("working", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(try readSession("t1", home: home)["title"] as? String, "Notch polish",
                       "a rename rewrites the file even though the state did not change")

        try append(#"{"type":"custom-title","customTitle":"","sessionId":"t1"}"#)
        try runScript("working", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(try readSession("t1", home: home)["title"] as? String, "Fix the notch \"margins\"",
                       "clearing the custom title falls back to the generated one")

        let missing = #"{"session_id":"t2","cwd":"/tmp/proj","transcript_path":"/nonexistent/t2.jsonl"}"#
        try runScript("working", payload: missing, home: home, noJQ: noJQ)
        XCTAssertEqual(try readSession("t2", home: home)["title"] as? String, "", "an unreadable transcript is not an error")
    }

    func testScriptLifecycleWithJq() throws {
        try XCTSkipIf(HookInstaller.jqPath() == nil, "jq is not installed on this machine")
        try lifecycle(noJQ: false)
    }

    func testScriptLifecycleWithoutJq() throws {
        try lifecycle(noJQ: true)
    }

    private func lifecycle(noJQ: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let home = self.home.appendingPathComponent(noJQ ? "plutil" : "jq", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let payload = #"{"session_id":"abc123","cwd":"/tmp/proj","hook_event_name":"SessionStart"}"#
        let file = sessionFile("abc123", home: home)

        // idle: the file appears with every field, correctly typed.
        var run = try runScript("idle", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(run.stdout, "", "hooks must not write to stdout")
        var session = try readSession("abc123", home: home)
        XCTAssertEqual(session["session_id"] as? String, "abc123")
        XCTAssertEqual(session["state"] as? String, "idle")
        XCTAssertEqual(session["cwd"] as? String, "/tmp/proj")
        XCTAssertEqual(session["term_program"] as? String, "TestTerm")
        XCTAssertEqual(session["idle"] as? Bool, false)
        XCTAssertEqual(session["title"] as? String, "", "no transcript_path: no name, but the key is there")
        XCTAssertNotNil(session["tty"] as? String)
        // The script walks up from its parent looking for a process named
        // claude. Under a plain test runner that is this process; when the
        // tests themselves run inside a Claude Code session it is that
        // session. Either way it must be a live process.
        let pid = try XCTUnwrap(session["pid"] as? Int)
        XCTAssertGreaterThan(pid, 0)
        XCTAssertEqual(kill(pid_t(pid), 0), 0, "pid \(pid) should be a running process")
        let ts = try XCTUnwrap(session["updated_at"] as? Int)
        XCTAssertGreaterThan(ts, 1_700_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path + ".tmp"))

        // Same state again: no rewrite.
        let before = try modificationDate(file)
        usleep(50_000)
        try runScript("idle", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(try modificationDate(file), before, "unchanged state must not rewrite")

        // A new state rewrites.
        try runScript("working", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(try readSession("abc123", home: home)["state"] as? String, "working")
        XCTAssertNotEqual(try modificationDate(file), before)

        try runScript("needs_you", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(try readSession("abc123", home: home)["state"] as? String, "needs_you")

        // idle_done → done with the idle flag; done afterwards clears it.
        try runScript("idle_done", payload: payload, home: home, noJQ: noJQ)
        session = try readSession("abc123", home: home)
        XCTAssertEqual(session["state"] as? String, "done")
        XCTAssertEqual(session["idle"] as? Bool, true)

        let idleStamp = try modificationDate(file)
        usleep(50_000)
        try runScript("idle_done", payload: payload, home: home, noJQ: noJQ)
        XCTAssertNotEqual(try modificationDate(file), idleStamp, "idle_done always writes")

        try runScript("done", payload: payload, home: home, noJQ: noJQ)
        session = try readSession("abc123", home: home)
        XCTAssertEqual(session["state"] as? String, "done")
        XCTAssertEqual(session["idle"] as? Bool, false)

        // gone deletes.
        run = try runScript("gone", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(run.status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        // No session id: nothing written. A slash in the id: nothing written.
        try runScript("idle", payload: #"{"cwd":"/tmp/proj"}"#, home: home, noJQ: noJQ)
        try runScript("idle", payload: #"{"session_id":"../evil","cwd":"/tmp"}"#, home: home, noJQ: noJQ)
        try runScript("idle", payload: "", home: home, noJQ: noJQ)
        let dir = home.appendingPathComponent(".claude-notch/sessions")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertEqual(files, [])

        // Unknown state: ignored, exit 0.
        run = try runScript("bogus", payload: payload, home: home, noJQ: noJQ)
        XCTAssertEqual(run.status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        // cwd falls back to CLAUDE_PROJECT_DIR.
        try runScript("idle", payload: #"{"session_id":"nocwd"}"#, home: home, noJQ: noJQ,
                      extraEnvironment: ["CLAUDE_PROJECT_DIR": "/tmp/fromenv"])
        XCTAssertEqual(try readSession("nocwd", home: home)["cwd"] as? String, "/tmp/fromenv")

        // Quotes and backslashes in strings survive the round trip.
        try runScript("idle", payload: #"{"session_id":"esc1","cwd":"/tmp/a\"b\\c"}"#, home: home, noJQ: noJQ)
        XCTAssertEqual(try readSession("esc1", home: home)["cwd"] as? String, #"/tmp/a"b\c"#)
    }
}
