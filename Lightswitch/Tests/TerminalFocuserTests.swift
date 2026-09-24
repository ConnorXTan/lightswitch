import XCTest
@testable import LightswitchKit

final class TerminalFocuserTests: XCTestCase {
    // MARK: Kind mapping

    func testEveryKnownTermProgramMaps() {
        let expected: [(String, TerminalKind)] = [
            ("iTerm.app", .iTerm),
            ("Apple_Terminal", .appleTerminal),
            ("vscode", .vscode),
            ("ghostty", .ghostty),
            ("kitty", .kitty),
            ("WezTerm", .wezterm),
            ("WarpTerminal", .warp),
            ("Hyper", .hyper),
            ("alacritty", .alacritty),
        ]
        for (program, kind) in expected {
            XCTAssertEqual(TerminalKind(termProgram: program), kind, program)
        }
    }

    func testMappingIsCaseInsensitiveAndTrimmed() {
        XCTAssertEqual(TerminalKind(termProgram: "ITERM.APP"), .iTerm)
        XCTAssertEqual(TerminalKind(termProgram: "apple_terminal"), .appleTerminal)
        XCTAssertEqual(TerminalKind(termProgram: "VSCode"), .vscode)
        XCTAssertEqual(TerminalKind(termProgram: "  wezterm\n"), .wezterm)
        XCTAssertEqual(TerminalKind(termProgram: "warpterminal"), .warp)
    }

    func testUnknownProgramsMapToUnknown() {
        XCTAssertEqual(TerminalKind(termProgram: ""), .unknown)
        XCTAssertEqual(TerminalKind(termProgram: "tmux"), .unknown)
        XCTAssertEqual(TerminalKind(termProgram: "SomethingElse"), .unknown)
    }

    func testBundleIdentifiersNonEmptyForKnownKinds() {
        for kind in TerminalKind.allCases where kind != .unknown {
            XCTAssertFalse(kind.bundleIdentifiers.isEmpty, "\(kind)")
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind)")
        }
        XCTAssertTrue(TerminalKind.unknown.bundleIdentifiers.isEmpty)
    }

    func testCursorIsReachableThroughVSCodeBundleIds() {
        XCTAssertTrue(TerminalKind.vscode.bundleIdentifiers.contains("com.todesktop.230313mzl4w4u92"))
    }

    // MARK: Scripts

    func testITermScriptSelectsSessionByDevicePath() throws {
        let script = try XCTUnwrap(TerminalFocuser.script(for: .iTerm, tty: "ttys004"))
        XCTAssertTrue(script.contains("\"/dev/ttys004\""))
        XCTAssertTrue(script.contains("iTerm"))
        XCTAssertTrue(script.contains("tty of s"))
        XCTAssertTrue(script.contains("activate"))
    }

    func testTerminalScriptSelectsTabByDevicePath() throws {
        let script = try XCTUnwrap(TerminalFocuser.script(for: .appleTerminal, tty: "ttys004"))
        XCTAssertTrue(script.contains("tty of t"))
        XCTAssertTrue(script.contains("\"/dev/ttys004\""))
        XCTAssertTrue(script.contains("selected tab"))
        XCTAssertTrue(script.contains("set index of w to 1"))
    }

    func testScriptIsNilForUnscriptableTerminals() {
        XCTAssertNil(TerminalFocuser.script(for: .vscode, tty: "ttys001"))
        XCTAssertNil(TerminalFocuser.script(for: .ghostty, tty: "ttys001"))
        XCTAssertNil(TerminalFocuser.script(for: .unknown, tty: "ttys001"))
    }

    func testDevPrefixIsAcceptedWithoutDoubling() throws {
        XCTAssertEqual(TerminalFocuser.devicePath(for: "ttys004"), "/dev/ttys004")
        XCTAssertEqual(TerminalFocuser.devicePath(for: "/dev/ttys004"), "/dev/ttys004")
        let script = try XCTUnwrap(TerminalFocuser.script(for: .iTerm, tty: "/dev/ttys004"))
        XCTAssertTrue(script.contains("\"/dev/ttys004\""))
        XCTAssertFalse(script.contains("/dev//dev/"))
    }

    func testQuotesAndBackslashesInTtyAreEscaped() throws {
        let script = try XCTUnwrap(TerminalFocuser.script(for: .iTerm, tty: "tty\"s\\1"))
        XCTAssertTrue(script.contains("\"/dev/tty\\\"s\\\\1\""))
        XCTAssertEqual(TerminalFocuser.appleScriptLiteral("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(TerminalFocuser.appleScriptLiteral("a\\b"), "\"a\\\\b\"")
    }
}
