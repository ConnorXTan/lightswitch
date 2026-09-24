import XCTest
@testable import LightswitchKit

final class IslandLayoutTests: XCTestCase {
    private func s(_ id: String) -> Session { Session(id: id, state: .working, cwd: "/p") }

    func testDotsAlternateSidesNearestTheNotchFirst() {
        let slotted: [Session?] = [s("1"), s("2"), s("3"), s("4"), s("5"), s("6")]
        XCTAssertEqual(IslandLayout.slots(slotted, side: .right).map { $0?.id }, ["1", "3", "5"])
        XCTAssertEqual(IslandLayout.slots(slotted, side: .left).map { $0?.id }, ["2", "4", "6"])
    }

    func testAWingKeepsEmptySlotsBeforeItsLastDot() {
        let slotted: [Session?] = [nil, s("2"), s("3"), nil, nil, s("6")]
        XCTAssertEqual(IslandLayout.slots(slotted, side: .right).map { $0?.id }, [nil, "3"])
        XCTAssertEqual(IslandLayout.slots(slotted, side: .left).map { $0?.id }, ["2", nil, "6"])
        XCTAssertEqual(IslandLayout.slots([nil, nil, nil, nil, nil, nil], side: .right).count, 0)
        XCTAssertEqual(IslandLayout.slots([], side: .left).count, 0)
    }

    func testWingWidthIsSymmetricAndGrowsWithTheFullerSide() {
        let one: [Session?] = [s("1"), nil, nil, nil, nil, nil]
        XCTAssertEqual(IslandLayout.wingWidth(one, overflow: 0), 36, "12 inner + dot + 16 outer")
        let two: [Session?] = [s("1"), s("2"), nil, nil, nil, nil]
        XCTAssertEqual(IslandLayout.wingWidth(two, overflow: 0), 36, "the second dot fills the other wing")
        let three: [Session?] = [s("1"), s("2"), s("3"), nil, nil, nil]
        XCTAssertEqual(IslandLayout.wingWidth(three, overflow: 0), 54)
        let six: [Session?] = [s("1"), s("2"), s("3"), s("4"), s("5"), s("6")]
        XCTAssertEqual(IslandLayout.wingWidth(six, overflow: 0), 72)
        XCTAssertEqual(IslandLayout.wingWidth(six, overflow: 2), 102, "+N (20 after a gap) sits on the right")
        XCTAssertEqual(IslandLayout.wingWidth([nil, nil, nil, nil, nil, nil], overflow: 0), 0)
    }
}
