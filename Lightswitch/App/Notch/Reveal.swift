import SwiftUI

/// Grows the panel out of the notch and shrinks it back in.
///
/// The panel keeps its final frame the whole time; what animates is a clip
/// that starts as the closed silhouette (the notch's width and height,
/// centred, closed radii) and expands to the panel's own outline. That is
/// symmetric about the notch, so nothing slides, and the content is
/// revealed rather than faded. The shadow is applied after the clip so it
/// follows the growing shape.
struct Reveal: ViewModifier, Animatable {
    var progress: CGFloat
    let closed: CGSize
    let lift: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .clipShape(RevealShape(progress: progress, closed: closed))
            .shadow(color: .black.opacity(lift * Double(max(0, min(1, progress)))),
                    radius: 14, x: 0, y: 8)
    }

    static func transition(closed: CGSize, lift: Double) -> AnyTransition {
        .modifier(active: Reveal(progress: 0, closed: closed, lift: lift),
                  identity: Reveal(progress: 1, closed: closed, lift: lift))
    }
}

/// The notch silhouette at some point between the closed size and `rect`,
/// centred at the top of `rect`.
struct RevealShape: Shape {
    var progress: CGFloat
    let closed: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = max(0, min(1, progress))
        let width = closed.width + (rect.width - closed.width) * p
        let height = closed.height + (rect.height - closed.height) * p
        let frame = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        let top = NotchMetrics.closedRadii.top + (NotchMetrics.openRadii.top - NotchMetrics.closedRadii.top) * p
        let bottom = NotchMetrics.closedRadii.bottom + (NotchMetrics.openRadii.bottom - NotchMetrics.closedRadii.bottom) * p
        return NotchShape(topRadius: top, bottomRadius: bottom).path(in: frame)
    }
}
