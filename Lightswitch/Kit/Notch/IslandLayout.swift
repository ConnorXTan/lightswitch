import Foundation

/// The closed notch as a floating island: a black capsule hanging just below
/// the screen edge, centred on the physical notch, with a wing either side.
/// The dots alternate sides (1st right, 2nd left, 3rd right …) so the island
/// stays balanced as sessions come and go, and both wings share one width
/// so it stays centred. Pure so the layout is testable.
public enum IslandLayout {
    public enum Side { case left, right }

    public static let dot: CGFloat = 8
    public static let gap: CGFloat = 10
    /// Space between the physical notch and the nearest dot.
    public static let innerInset: CGFloat = 12
    /// Space between the farthest dot and the capsule's end.
    public static let outerInset: CGFloat = 16
    public static let overflowWidth: CGFloat = 20
    /// How far below the screen edge the island hangs.
    public static let topGap: CGFloat = 5
    /// How far past the notch's bottom edge the island reaches, hiding the
    /// notch's own rounded corners.
    public static let bottomOverhang: CGFloat = 1

    /// The slots a wing shows, nearest the notch first: the right wing takes
    /// slots 1, 3, 5 and the left 2, 4, 6, each trimmed after its last
    /// occupied slot so a dot keeps its place when the ones before it leave.
    public static func slots(_ slotted: [Session?], side: Side) -> [Session?] {
        let start = side == .right ? 0 : 1
        guard start < slotted.count else { return [] }
        let picked = stride(from: start, to: slotted.count, by: 2).map { slotted[$0] }
        guard let last = picked.lastIndex(where: { $0 != nil }) else { return [] }
        return Array(picked[...last])
    }

    /// Width of one wing holding `dots` dots and, on the right, a "+N".
    public static func sideWidth(dots: Int, overflow: Int) -> CGFloat {
        guard dots > 0 || overflow > 0 else { return 0 }
        var row = CGFloat(dots) * dot + CGFloat(max(0, dots - 1)) * gap
        if overflow > 0 { row += (dots > 0 ? gap : 0) + overflowWidth }
        return innerInset + row + outerInset
    }

    /// The width both wings take: whichever side needs more, so the island
    /// is symmetric about the notch. Zero with no sessions, when the island
    /// is just the notch.
    public static func wingWidth(_ slotted: [Session?], overflow: Int) -> CGFloat {
        max(sideWidth(dots: slots(slotted, side: .right).count, overflow: overflow),
            sideWidth(dots: slots(slotted, side: .left).count, overflow: 0))
    }
}
