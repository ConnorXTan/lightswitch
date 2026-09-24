import AppKit
import SwiftUI
import LightswitchKit

/// Open/closed state for one display's notch. One instance per window; all
/// of them render the same shared session list.
@MainActor
final class NotchViewModel: ObservableObject {
    enum State { case closed, open }

    let screenUUID: String?
    @Published private(set) var state: State = .closed
    @Published private(set) var closedSize: CGSize
    @Published private(set) var hasNotch: Bool

    init(screen: NSScreen) {
        screenUUID = screen.displayUUID
        closedSize = NotchGeometry.closedSize(for: screen)
        hasNotch = NotchGeometry.hasNotch(screen)
    }

    var screen: NSScreen? {
        screenUUID.flatMap(NSScreen.screen(withUUID:))
    }

    var isOpen: Bool { state == .open }

    /// Height of the closed island. On a notched display it hangs
    /// `IslandLayout.topGap` below the screen edge and reaches just past the
    /// notch's bottom; elsewhere it is a pill the height of the menu bar.
    var islandHeight: CGFloat {
        hasNotch ? closedSize.height - IslandLayout.topGap + IslandLayout.bottomOverhang : closedSize.height
    }

    func open() { state = .open }
    func close() { state = .closed }
    func toggle() { state == .open ? close() : open() }

    /// Re-measure after a display change; the notch height can differ between
    /// a notched panel and an external monitor's menu bar.
    func refreshSize() {
        guard let screen else { return }
        closedSize = NotchGeometry.closedSize(for: screen)
        hasNotch = NotchGeometry.hasNotch(screen)
    }
}
