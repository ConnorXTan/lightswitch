import XCTest
@testable import LightswitchKit

final class WingLayoutTests: XCTestCase {
    private func s(_ id: String) -> Session { Session(id: id, state: .working, cwd: "/p") }

    func testSlotsFillColumnsTopToBottomThenLeftToRight() {
        let slotted: [Session?] = [s("1"), s("2"), s("3"), s("4"), s("5"), s("6")]
        let cols = WingLayout.columns(slotted).map { $0.map { $0?.id } }
        XCTAssertEqual(cols, [["1", "2"], ["3", "4"], ["5", "6"]])
    }

    func testTrailingEmptyColumnsAreDroppedButGapsInsideAreKept() {
        let slotted: [Session?] = [nil, s("2"), nil, nil, s("5"), nil]
        let cols = WingLayout.columns(slotted).map { $0.map { $0?.id } }
        XCTAssertEqual(cols, [[nil, "2"], [nil, nil], ["5", nil]])
        XCTAssertEqual(WingLayout.columns([s("1"), nil, nil, nil, nil, nil]).count, 1)
        XCTAssertEqual(WingLayout.columns([nil, nil, nil, nil, nil, nil]).count, 0)
        XCTAssertEqual(WingLayout.columns([]).count, 0)
    }

    func testWingWidthGrowsOnlyEveryOtherSession() {
        let one: [Session?] = [s("1"), nil, nil, nil, nil, nil]
        let two: [Session?] = [s("1"), s("2"), nil, nil, nil, nil]
        let three: [Session?] = [s("1"), s("2"), s("3"), nil, nil, nil]
        let six: [Session?] = [s("1"), s("2"), s("3"), s("4"), s("5"), s("6")]
        XCTAssertEqual(WingLayout.wingWidth(one, overflow: 0), 27, "8 leading + one 7 pt column + 12 trailing")
        XCTAssertEqual(WingLayout.wingWidth(two, overflow: 0), 27, "the second dot goes under the first")
        XCTAssertEqual(WingLayout.wingWidth(three, overflow: 0), 39)
        XCTAssertEqual(WingLayout.wingWidth(six, overflow: 0), 51)
        XCTAssertEqual(WingLayout.wingWidth(six, overflow: 1), 72, "+N is 16 pt after a 5 pt gap")
        XCTAssertEqual(WingLayout.wingWidth([nil, nil, nil, nil, nil, nil], overflow: 0), 0)
    }
}
