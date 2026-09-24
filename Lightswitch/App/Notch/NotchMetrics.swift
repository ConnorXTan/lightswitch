import SwiftUI

/// Fixed sizes and timings for the notch UI. The closed size is measured per
/// screen at runtime (see `NotchGeometry`); everything here is a design
/// decision rather than a measurement.
enum NotchMetrics {
    /// The transparent canvas each window draws into. Wide enough for the
    /// alert peek, tall enough for the open list plus its shadow.
    static let windowSize = CGSize(width: 640, height: 280)

    /// Width of the open panel.
    static let openWidth: CGFloat = 400
    /// Width of the closed shape while an alert peek is showing.
    static let peekWidth: CGFloat = 640

    /// Horizontal inset of content inside the closed shape.
    static let closedInset: CGFloat = 10
    static let openInset: CGFloat = 10

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
