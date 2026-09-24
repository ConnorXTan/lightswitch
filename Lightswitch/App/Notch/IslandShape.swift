import SwiftUI

/// The island's outline: a continuous-corner rounded rectangle. Closed, the
/// radius is half the height, so it is a capsule; open, it relaxes to a
/// panel radius. The radius animates, which is what makes opening read as
/// the island swelling rather than a panel appearing under it.
struct IslandShape: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
    }
}
