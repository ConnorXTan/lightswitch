import XCTest
@testable import LightswitchKit

final class TerminalWindowTests: XCTestCase {
    func testThisProcessKnowsItsParentAndDirectory() {
        XCTAssertEqual(TerminalWindow.parentProcess(of: getpid()), getppid())
        XCTAssertEqual(TerminalWindow.currentDirectory(of: getpid()).map(ProjectRoot.normalize),
                       ProjectRoot.normalize(FileManager.default.currentDirectoryPath))
        XCTAssertNil(TerminalWindow.parentProcess(of: 2_000_000_000))
        XCTAssertNil(TerminalWindow.currentDirectory(of: 2_000_000_000))
    }

    func testOpenFoldersComeFromTheStateFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalWindowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("storage.json")
        try #"""
        {"windowsState":{
          "lastActiveWindow":{"folder":"file:///Users/c/Documents/GitHub/Ascii%20Prism","uiState":{}},
          "openedWindows":[
            {"folder":"file:///Users/c/Documents/GitHub/Ascii%20Prism","uiState":{}},
            {"workspace":{"id":"abc","configPath":"file:///Users/c/x.code-workspace"}},
            {"folder":"file:///Users/c/Documents/GitHub/lightswitch/"},
            {"folder":"vscode-remote://ssh-remote+box/home/c/proj"}
          ]},
         "other":1}
        """#.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(TerminalWindow.openFolders(inStorageFile: file),
                       ["/Users/c/Documents/GitHub/Ascii Prism", "/Users/c/Documents/GitHub/lightswitch"])
        XCTAssertEqual(TerminalWindow.openFolders(inStorageFile: dir.appendingPathComponent("missing.json")), [])
        XCTAssertEqual(TerminalWindow.storageFiles(applicationSupport: dir), [], "none of the editors' files exist here")
    }

    func testWindowFolderTrustsTheShellFirstAndWalksUp() {
        let repo = "/Users/c/GitHub/Ascii Prism"
        let worktree = repo + "/.claude/worktrees/onboard"
        let open = [repo, "/Users/c/GitHub/lightswitch"]

        // The shell sits at the repo root while the session moved into a
        // worktree: the repo's window is the one with the terminal.
        XCTAssertEqual(TerminalWindow.windowFolder(candidates: [repo, worktree], open: open), repo)
        // No shell known: walk up from the session's own directory.
        XCTAssertEqual(TerminalWindow.windowFolder(candidates: [worktree], open: open), repo)
        // A window opened on the worktree itself is nearer, so it wins.
        XCTAssertEqual(TerminalWindow.windowFolder(candidates: [worktree], open: open + [worktree]), worktree)
        // Nothing open above it.
        XCTAssertNil(TerminalWindow.windowFolder(candidates: ["/Users/c/Other/proj"], open: open))
        XCTAssertNil(TerminalWindow.windowFolder(candidates: [], open: open))
        XCTAssertNil(TerminalWindow.windowFolder(candidates: [""], open: open))
    }
}
