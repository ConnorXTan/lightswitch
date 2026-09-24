import SwiftUI

/// Grows the panel out of the notch and shrinks it back in.
///
/// The panel keeps its final frame the whole time; what animates is a clip
/// that starts as the whole closed box (the notch plus its wing, where the
/// dots are, closed radii) and expands to the panel's own outline in one
/// motion. The content is revealed rather than faded, and the shadow is
/// applied after the clip so it follows the growing shape.
struct Reveal: ViewModifier, Animatable {
    var progress: CGFloat
    let closed: CGSize
    let wing: CGFloat
    let lift: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .clipShape(RevealShape(progress: progress, closed: closed, wing: wing))
            .shadow(color: .black.opacity(lift * Double(max(0, min(1, progress)))),
                    radius: 14, x: 0, y: 8)
    }

    static func transition(closed: CGSize, wing: CGFloat, lift: Double) -> AnyTransition {
        .modifier(active: Reveal(progress: 0, closed: closed, wing: wing, lift: lift),
                  identity: Reveal(progress: 1, closed: closed, wing: wing, lift: lift))
    }
}

/// The notch silhouette at some point between the closed box and `rect`.
/// The closed box is the notch (centred in `rect`) plus its wing to the
/// right, exactly where `ClosedLayout` draws it.
struct RevealShape: Shape {
    var progress: CGFloat
    let closed: CGSize
    let wing: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = max(0, min(1, progress))
        let start = CGRect(x: rect.midX - closed.width / 2, y: rect.minY,
                           width: closed.width + wing, height: closed.height)
        let frame = CGRect(x: start.minX + (rect.minX - start.minX) * p,
                           y: rect.minY,
                           width: start.width + (rect.width - start.width) * p,
                           height: start.height + (rect.height - start.height) * p)
        let top = NotchMetrics.closedRadii.top + (NotchMetrics.openRadii.top - NotchMetrics.closedRadii.top) * p
        let bottom = NotchMetrics.closedRadii.bottom + (NotchMetrics.openRadii.bottom - NotchMetrics.closedRadii.bottom) * p
        return NotchShape(topRadius: top, bottomRadius: bottom).path(in: frame)
    }
}
