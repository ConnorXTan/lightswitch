import SwiftUI

/// Fixed sizes and timings for the notch UI. The closed size is measured per
/// screen at runtime (see `NotchGeometry`); everything here is a design
/// decision rather than a measurement.
enum NotchMetrics {
    /// The transparent canvas each window draws into. Wide enough for the
    /// alert peek, tall enough for the open list plus its shadow.
    static let windowSize = CGSize(width: 640, height: 360)

    /// Width of the open panel. Beside the header's clear notch gap this
    /// leaves 87 pt a side, enough for "Claude Code" (70 pt) and
    /// "12 terminals" (65 pt) on one line.
    static let openWidth: CGFloat = 440
    /// Width of the closed shape while an alert peek is showing.
    static let peekWidth: CGFloat = 640

    /// Horizontal inset of content inside the closed shape.
    static let closedInset: CGFloat = 10
    /// Bottom inset of the open panel's content.
    static let openInset: CGFloat = 10
    /// Horizontal inset of the open panel's content. The shape's sides sit
    /// inside its flared top corners by the top radius, so this is the
    /// flare plus the margin that actually shows (14 pt to the text).
    static let openSideInset: CGFloat = openRadii.top + 4

    static let closedRadii = (top: CGFloat(6), bottom: CGFloat(14))
    static let openRadii = (top: CGFloat(19), bottom: CGFloat(24))

    /// Hover has to persist this long before the notch opens, so passing the
    /// cursor over the menu bar does not flap it.
    static let hoverOpenDelay: Duration = .milliseconds(300)
    /// Mouse-out closes after this debounce, so a wobble at the edge holds.
    static let hoverCloseDelay: Duration = .milliseconds(100)

    static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0)
    static let peekAnimation = Animation.smooth(duration: 0.3)
}
