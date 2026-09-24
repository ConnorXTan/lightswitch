import XCTest
@testable import LightswitchKit

final class ProjectRootTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectRootTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func mkdir(_ rel: String) throws -> String {
        let url = base.appendingPathComponent(rel, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func write(_ rel: String, _ text: String) throws {
        let url = base.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testSubfolderResolvesToTheRepositoryRoot() throws {
        let repo = try mkdir("repo")
        _ = try mkdir("repo/.git")
        let sub = try mkdir("repo/src/deep")
        XCTAssertEqual(ProjectRoot.resolve(sub), repo)
        XCTAssertEqual(ProjectRoot.resolve(repo), repo)
        XCTAssertEqual(ProjectRoot.resolve(repo + "/src/../src/./deep/"), repo, "odd spellings fold")
    }

    func testLinkedWorktreeResolvesToTheMainWorktree() throws {
        let repo = try mkdir("repo")
        _ = try mkdir("repo/.git/worktrees/onboard")
        try write("repo/.git/worktrees/onboard/commondir", "../..\n")
        let worktree = try mkdir("repo/.claude/worktrees/onboard")
        try write("repo/.claude/worktrees/onboard/.git", "gitdir: \(repo)/.git/worktrees/onboard\n")
        XCTAssertEqual(ProjectRoot.resolve(worktree), repo)
        XCTAssertEqual(ProjectRoot.resolve(worktree + "/Sources"), repo, "a subfolder of the worktree")
    }

    func testWorktreeKeptElsewhereWithoutCommondirResolves() throws {
        let repo = try mkdir("repo")
        _ = try mkdir("repo/.git/worktrees/feature")
        let worktree = try mkdir("repo-feature")
        try write("repo-feature/.git", "gitdir: \(repo)/.git/worktrees/feature\n")
        XCTAssertEqual(ProjectRoot.resolve(worktree), repo)
    }

    func testDeletedWorktreeFallsBackToTheRepositoryAbove() throws {
        let repo = try mkdir("repo")
        _ = try mkdir("repo/.git")
        XCTAssertEqual(ProjectRoot.resolve(repo + "/.claude/worktrees/gone"), repo)
    }

    func testSubmoduleIsItsOwnProject() throws {
        _ = try mkdir("repo/.git/modules/lib")
        let lib = try mkdir("repo/lib")
        try write("repo/lib/.git", "gitdir: ../.git/modules/lib\n")
        XCTAssertEqual(ProjectRoot.resolve(lib), lib)
    }

    func testFolderOutsideAnyRepositoryIsItsOwnProject() throws {
        let plain = try mkdir("plain/notes")
        XCTAssertEqual(ProjectRoot.resolve(plain), plain)
        XCTAssertEqual(ProjectRoot.resolve(""), "")
    }

    func testNormalizeFoldsDotsAndSlashes() {
        XCTAssertEqual(ProjectRoot.normalize("/a/b/../c/./d//"), "/a/c/d")
        XCTAssertEqual(ProjectRoot.normalize("/../.."), "/")
        XCTAssertEqual(ProjectRoot.normalize("/"), "/")
    }
}
