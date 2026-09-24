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

    /// Open and close happen inside an animation transaction: the layouts
    /// swap with transitions, and only a transaction animates those (an
    /// `.animation(value:)` modifier on the container does not).
    func open() {
        guard state != .open else { return }
        Log.note(Log.app, "open")
        withAnimation(NotchMetrics.openAnimation) { state = .open }
    }

    func close() {
        guard state != .closed else { return }
        Log.note(Log.app, "close")
        withAnimation(NotchMetrics.closeAnimation) { state = .closed }
    }

    func toggle() { state == .open ? close() : open() }

    /// Re-measure after a display change; the notch height can differ between
    /// a notched panel and an external monitor's menu bar.
    func refreshSize() {
        guard let screen else { return }
        closedSize = NotchGeometry.closedSize(for: screen)
        hasNotch = NotchGeometry.hasNotch(screen)
    }
}
