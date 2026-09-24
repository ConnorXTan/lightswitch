import SwiftUI
import LightswitchKit

/// Sizing shared by the dots and by the closed-notch layout that has to know
/// how wide the wing holding them will be, so the shape can be offset to keep
/// the physical notch covered exactly.
enum DotMetrics {
    static let diameter: CGFloat = 8
    static let gap: CGFloat = 10
    /// Space between the physical notch and the first dot.
    static let insetLeading: CGFloat = 12
    /// Space after the last dot. The shape's body sits inside its flared top
    /// corners by the top radius (6 pt), so this is 12 pt of visible margin.
    static let insetTrailing: CGFloat = 18
    static let overflowWidth: CGFloat = 20

    /// How many slot positions are drawn: up to the highest occupied slot, so
    /// a session keeps its place when the ones before it leave.
    static func slotsShown(_ slotted: [Session?]) -> Int {
        (slotted.lastIndex { $0 != nil }).map { $0 + 1 } ?? 0
    }

    static func rowWidth(slots: Int, overflow: Int) -> CGFloat {
        guard slots > 0 else { return 0 }
        var w = CGFloat(slots) * diameter + CGFloat(slots - 1) * gap
        if overflow > 0 { w += gap + overflowWidth }
        return w
    }

    static func wingWidth(slots: Int, overflow: Int) -> CGFloat {
        let row = rowWidth(slots: slots, overflow: overflow)
        return row > 0 ? row + insetLeading + insetTrailing : 0
    }
}

/// One dot per slot, in slot order, plus a "+N" when more sessions exist
/// than slots. Empty slots keep their space so positions never shift.
struct DotsRow: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        let slotted = store.slotted
        let shown = DotMetrics.slotsShown(slotted)
        HStack(spacing: DotMetrics.gap) {
            ForEach(0..<shown, id: \.self) { index in
                SessionDot(session: slotted[index],
                           acknowledged: slotted[index].map { store.isAcknowledged($0.id) } ?? true)
                    .contentShape(Rectangle().inset(by: -5))
                    .onTapGesture {
                        if let session = slotted[index] { NotchCoordinator.shared.select(session) }
                    }
            }
            if !store.overflow.isEmpty {
                Text("+\(store.overflow.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: DotMetrics.overflowWidth, alignment: .leading)
                    .accessibilityLabel("\(store.overflow.count) more sessions")
            }
        }
        .animation(.smooth(duration: 0.25), value: shown)
    }
}

/// A single status dot. Red and unacknowledged: it pulses. Done and idle
/// (Claude has been waiting a while): it breathes slowly. With Reduce Motion
/// on, the red dot gets a ring instead of a pulse.
struct SessionDot: View {
    let session: Session?
    let acknowledged: Bool
    var size: CGFloat = DotMetrics.diameter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    private var pulsing: Bool {
        guard let session else { return false }
        return session.state == .needsYou && !acknowledged && !reduceMotion
    }

    private var breathing: Bool {
        guard let session else { return false }
        return session.state == .done && session.idle && !reduceMotion
    }

    private var ringed: Bool {
        guard let session else { return false }
        return session.state == .needsYou && !acknowledged && reduceMotion
    }

    var body: some View {
        ZStack {
            if let session {
                Circle()
                    .fill(session.state.color)
                    .frame(width: size, height: size)
                    .scaleEffect(pulsing && phase ? 1.4 : 1)
                    .opacity(breathing && phase ? 0.45 : 1)
                    .shadow(color: session.state.color.opacity(pulsing ? (phase ? 0.9 : 0.35) : 0),
                            radius: pulsing && phase ? 5 : 2, x: 0, y: 0)
                    .overlay {
                        if ringed {
                            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                                .frame(width: size + 6, height: size + 6)
                        }
                    }
                    .accessibilityLabel("\(session.projectName) \(session.state.announcement)")
            }
        }
        .frame(width: size, height: size)
        .animation(animation, value: phase)
        .onAppear { phase = pulsing || breathing }
        .onChange(of: pulsing) { _, new in phase = new || breathing }
        .onChange(of: breathing) { _, new in phase = pulsing || new }
    }

    private var animation: Animation {
        if pulsing { return .easeInOut(duration: 0.8).repeatForever(autoreverses: true) }
        if breathing { return .easeInOut(duration: 2.2).repeatForever(autoreverses: true) }
        return .easeOut(duration: 0.2)
    }
}
