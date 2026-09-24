import XCTest
@testable import LightswitchKit

@MainActor
final class SessionStoreTests: XCTestCase {
    private var dir: URL!
    private var store: SessionStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = SessionStore(directory: dir)
    }

    override func tearDown() async throws {
        store.stop()
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ id: String, state: String, cwd: String = "/tmp/x", pid: Int = 1,
                       idle: Bool = false, updatedAt: Int = 1_758_700_000) throws {
        let json = """
        {"session_id":"\(id)","state":"\(state)","cwd":"\(cwd)","pid":\(pid),"tty":"ttys004","term_program":"vscode","idle":\(idle),"updated_at":\(updatedAt)}
        """
        try json.write(to: dir.appendingPathComponent("\(id).json"), atomically: true, encoding: .utf8)
    }

    private func remove(_ id: String) throws {
        try FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
    }

    // MARK: Decoding

    func testDecodesTheHookFileFormat() throws {
        try write("7f1c", state: "needs_you", cwd: "/Users/connortan/lightswitch", pid: 48213)
        store.reload()
        let s = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(s.id, "7f1c")
        XCTAssertEqual(s.state, .needsYou)
        XCTAssertEqual(s.folderName, "lightswitch")
        XCTAssertEqual(s.pid, 48213)
        XCTAssertEqual(s.tty, "ttys004")
        XCTAssertEqual(s.termProgram, "vscode")
        XCTAssertFalse(s.idle)
        XCTAssertEqual(s.updatedAt.timeIntervalSince1970, 1_758_700_000)
    }

    func testUnknownStateDegradesToIdleAndTmpFilesAreIgnored() throws {
        try write("a", state: "mystery")
        try "{}".write(to: dir.appendingPathComponent("b.json.tmp"), atomically: true, encoding: .utf8)
        try "not json".write(to: dir.appendingPathComponent("c.json"), atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertEqual(store.sessions.map(\.id), ["a"])
        XCTAssertEqual(store.sessions.first?.state, .idle)
    }

    func testSessionRoundTripsThroughCodable() throws {
        let s = Session(id: "abcd1234", state: .done, cwd: "/tmp/p", pid: 7, tty: "ttys001",
                        termProgram: "iTerm.app", idle: true,
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.shortID, "1234")
    }

    // MARK: Slots

    func testSlotsAreAssignedInOrderOfAppearanceAndStayPut() throws {
        try write("a", state: "working")
        store.reload()
        try write("b", state: "working")
        store.reload()
        try write("c", state: "working")
        store.reload()
        XCTAssertEqual(store.slot(of: "a"), 1)
        XCTAssertEqual(store.slot(of: "b"), 2)
        XCTAssertEqual(store.slot(of: "c"), 3)

        try remove("b")
        store.reload()
        XCTAssertEqual(store.slotted.map { $0?.id }, ["a", nil, "c", nil])

        try write("d", state: "idle")
        store.reload()
        XCTAssertEqual(store.slot(of: "d"), 2, "the freed middle slot is reused")
        XCTAssertEqual(store.slotted.map { $0?.id }, ["a", "d", "c", nil])
    }

    func testBatchArrivalsAreOrderedByLastUpdate() throws {
        try write("zz", state: "working", updatedAt: 300)
        try write("mm", state: "working", updatedAt: 100)
        try write("aa", state: "working", updatedAt: 200)
        store.reload()
        XCTAssertEqual(store.sessions.map(\.id), ["mm", "aa", "zz"])
        XCTAssertEqual(store.slot(of: "mm"), 1)
        XCTAssertEqual(store.slot(of: "zz"), 3)
    }

    func testFifthSessionOverflows() throws {
        for id in ["a", "b", "c", "d", "e"] {
            try write(id, state: "working")
            store.reload()
        }
        XCTAssertNil(store.slot(of: "e"))
        XCTAssertEqual(store.overflow.map(\.id), ["e"])
        XCTAssertEqual(store.sessions.map(\.id), ["a", "b", "c", "d", "e"])

        try remove("a")
        store.reload()
        XCTAssertEqual(store.slot(of: "e"), 1, "overflow takes the first freed slot")
        XCTAssertTrue(store.overflow.isEmpty)
    }

    func testReAddedSessionGetsAFreshSlot() throws {
        try write("a", state: "working")
        try write("b", state: "working")
        store.reload()
        try remove("a")
        store.reload()
        try write("a", state: "working")
        store.reload()
        XCTAssertEqual(store.slot(of: "a"), 1)
        XCTAssertEqual(store.sessions.map(\.id), ["a", "b"])
    }

    // MARK: Alerts and acknowledgement

    func testTurningRedPublishesExactlyOneAlert() throws {
        try write("a", state: "working")
        store.reload()
        XCTAssertNil(store.alert)

        try write("a", state: "needs_you")
        store.reload()
        XCTAssertEqual(store.alert?.session.id, "a")
        let first = store.alert

        // Still red, touched again: no new alert.
        try write("a", state: "needs_you", updatedAt: 1_758_700_100)
        store.reload()
        XCTAssertEqual(store.alert, first)

        // Back to working then red again: a second alert.
        try write("a", state: "working")
        store.reload()
        try write("a", state: "needs_you", updatedAt: 1_758_700_200)
        store.reload()
        XCTAssertNotEqual(store.alert, first)
    }

    func testNewFileAlreadyRedAlerts() throws {
        try write("a", state: "needs_you")
        store.reload()
        XCTAssertEqual(store.alert?.session.id, "a")
    }

    func testAcknowledgeResetsWhenStateChanges() throws {
        try write("a", state: "needs_you")
        store.reload()
        XCTAssertEqual(store.needingAttention.map(\.id), ["a"])

        store.acknowledge("a")
        XCTAssertTrue(store.isAcknowledged("a"))
        XCTAssertTrue(store.needingAttention.isEmpty)
        XCTAssertEqual(store.sessions.first?.state, .needsYou, "the dot stays red")

        try write("a", state: "working")
        store.reload()
        XCTAssertFalse(store.isAcknowledged("a"))

        store.acknowledge("zzz")
        XCTAssertFalse(store.isAcknowledged("zzz"), "unknown ids are ignored")
    }

    func testNeedingAttentionIsOldestFirst() throws {
        try write("late", state: "needs_you", updatedAt: 200)
        try write("early", state: "needs_you", updatedAt: 100)
        store.reload()
        XCTAssertEqual(store.needingAttention.map(\.id), ["early", "late"])
    }

    // MARK: Pruning and watching

    func testPruneRemovesDeadProcessesAndKeepsLiveOnes() throws {
        try write("live", state: "working", pid: 1)
        try write("dead", state: "working", pid: 2_000_000_000)
        try write("unknown", state: "working", pid: 0)
        store.reload()
        XCTAssertEqual(store.sessions.count, 3)

        store.prune()
        XCTAssertEqual(Set(store.sessions.map(\.id)), ["live", "unknown"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("dead.json").path))
    }

    func testWatchingPicksUpNewFiles() async throws {
        store.start()
        XCTAssertTrue(store.sessions.isEmpty)
        try write("w", state: "working")
        let deadline = Date().addingTimeInterval(3)
        while store.sessions.isEmpty && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(store.sessions.map(\.id), ["w"])

        try remove("w")
        let deadline2 = Date().addingTimeInterval(3)
        while !store.sessions.isEmpty && Date() < deadline2 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(store.sessions.isEmpty)
    }

    // MARK: Projects

    func testSessionsGroupByWorkingDirectoryInFirstAppearanceOrder() throws {
        try write("a", state: "working", cwd: "/Users/connortan/Documents/GitHub/lightswitch", updatedAt: 100)
        try write("b", state: "needs_you", cwd: "/Users/connortan/MARs/MARS", updatedAt: 200)
        try write("c", state: "idle", cwd: "/Users/connortan/Documents/GitHub/lightswitch", updatedAt: 300)
        store.reload()
        let groups = store.groups
        XCTAssertEqual(groups.map(\.name), ["lightswitch", "MARS"])
        XCTAssertEqual(groups[0].sessions.map(\.id), ["a", "c"])
        XCTAssertEqual(groups[0].attention, .working)
        XCTAssertEqual(groups[1].attention, .needsYou)
        XCTAssertEqual(groups[0].location, "~/Documents/GitHub")
    }

    func testGroupWithoutAWorkingDirectoryIsStillListed() {
        let g = ProjectGroup(cwd: "", sessions: [Session(id: "x1234", state: .idle, cwd: "")])
        XCTAssertEqual(g.name, "untitled")
        XCTAssertEqual(g.location, "")
    }

    func testTerminalLabelNamesTheAppAndTheTab() {
        XCTAssertEqual(Session(id: "abcd9999", state: .idle, cwd: "/p", tty: "ttys004", termProgram: "vscode").terminalLabel,
                       "VS Code · ttys004")
        XCTAssertEqual(Session(id: "abcd9999", state: .idle, cwd: "/p", tty: "", termProgram: "").terminalLabel,
                       "Terminal · 9999")
    }

    // MARK: Age

    func testAgeFormatting() {
        let base = Date(timeIntervalSince1970: 10_000)
        let s = Session(id: "x", state: .idle, cwd: "/", updatedAt: base)
        XCTAssertEqual(s.age(at: base.addingTimeInterval(2)), "now")
        XCTAssertEqual(s.age(at: base.addingTimeInterval(42)), "42s")
        XCTAssertEqual(s.age(at: base.addingTimeInterval(200)), "3m")
        XCTAssertEqual(s.age(at: base.addingTimeInterval(7200)), "2h")
        XCTAssertEqual(s.age(at: base.addingTimeInterval(200_000)), "2d")
        XCTAssertEqual(s.age(at: base.addingTimeInterval(-5)), "now", "clock skew never goes negative")
    }

    func testFolderNameFallsBackToPath() {
        XCTAssertEqual(Session(id: "x", state: .idle, cwd: "/Users/c/proj").folderName, "proj")
        XCTAssertEqual(Session(id: "x", state: .idle, cwd: "/").folderName, "/")
        XCTAssertEqual(Session(id: "x", state: .idle, cwd: "").folderName, "")
    }
}
