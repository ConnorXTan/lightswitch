import Foundation

/// The closed notch's wing: a black extension to the right of the physical
/// notch holding one dot per session in a two-row grid, so six sessions take
/// three columns. Kept narrow so the menu bar extras beside the notch stay
/// uncovered. Pure so the sizes are testable.
public enum WingLayout {
    public static let dot: CGFloat = 7
    public static let gap: CGFloat = 5
    public static let rows = 2
    /// Space between the physical notch and the first column.
    public static let leadingInset: CGFloat = 8
    /// Space after the last column. The shape's body sits inside its flared
    /// top corner by the top radius (6 pt), so this is 6 pt of visible margin.
    public static let trailingInset: CGFloat = 12
    public static let overflowWidth: CGFloat = 16

    /// The slots as columns of `rows`, filled top to bottom then left to
    /// right (slot 1 top-left, slot 2 under it, slot 3 tops the next column),
    /// trimmed after the last column holding a session so a dot keeps its
    /// place when the ones before it leave.
    public static func columns(_ slotted: [Session?]) -> [[Session?]] {
        var cols: [[Session?]] = stride(from: 0, to: slotted.count, by: rows).map { start in
            (0..<rows).map { start + $0 < slotted.count ? slotted[start + $0] : nil }
        }
        while let last = cols.last, last.allSatisfy({ $0 == nil }) { cols.removeLast() }
        return cols
    }

    public static func rowWidth(columns: Int, overflow: Int) -> CGFloat {
        guard columns > 0 || overflow > 0 else { return 0 }
        var w = CGFloat(columns) * dot + CGFloat(max(0, columns - 1)) * gap
        if overflow > 0 { w += (columns > 0 ? gap : 0) + overflowWidth }
        return w
    }

    /// The wing's full width, or zero with no sessions (then the closed shape
    /// is just the notch).
    public static func wingWidth(_ slotted: [Session?], overflow: Int) -> CGFloat {
        let row = rowWidth(columns: columns(slotted).count, overflow: overflow)
        return row > 0 ? row + leadingInset + trailingInset : 0
    }
}
