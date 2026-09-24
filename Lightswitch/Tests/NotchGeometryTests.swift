import XCTest
@testable import LightswitchKit

final class NotchGeometryTests: XCTestCase {
    func testNotchedDisplayUsesAuxiliaryAreasPlusBleed() {
        // 14-inch MacBook Pro: 1512 wide, aux areas ~ 674 each, notch 164.
        let size = NotchGeometry.closedSize(screenWidth: 1512, leftAuxWidth: 674, rightAuxWidth: 674,
                                            safeAreaTop: 32, menuBarHeight: 32)
        XCTAssertEqual(size.width, 164 + 4)
        XCTAssertEqual(size.height, 32)
    }

    func testExternalDisplayFallsBackToMenuBarHeightAndFixedWidth() {
        let size = NotchGeometry.closedSize(screenWidth: 2560, leftAuxWidth: nil, rightAuxWidth: nil,
                                            safeAreaTop: 0, menuBarHeight: 24)
        XCTAssertEqual(size.width, NotchGeometry.fallbackWidth)
        XCTAssertEqual(size.height, 24)
    }

    func testNothingMeasurableStillProducesAUsableShape() {
        let size = NotchGeometry.closedSize(screenWidth: 1000, leftAuxWidth: 0, rightAuxWidth: 0,
                                            safeAreaTop: 0, menuBarHeight: 0)
        XCTAssertEqual(size.width, NotchGeometry.fallbackWidth)
        XCTAssertEqual(size.height, NotchGeometry.fallbackHeight)
    }

    func testNotchCentreFollowsTheAuxiliaryAreas() {
        // This 14-inch: left 665, right 662 → notch centre 757.5, not 756.
        XCTAssertEqual(NotchGeometry.notchCenterX(screenMinX: 0, screenWidth: 1512,
                                                  leftAuxWidth: 665, rightAuxWidth: 662), 757.5)
        XCTAssertEqual(NotchGeometry.notchCenterX(screenMinX: 1512, screenWidth: 2560,
                                                  leftAuxWidth: nil, rightAuxWidth: nil), 1512 + 1280)
    }

    func testPreferencesRegisterDefaults() {
        let suite = UserDefaults(suiteName: "NotchGeometryTests.\(UUID().uuidString)")!
        Preferences.register(in: suite)
        XCTAssertTrue(suite.bool(forKey: Preferences.showOnAllDisplaysKey))
        XCTAssertTrue(suite.bool(forKey: Preferences.alertSoundKey))
    }
}
