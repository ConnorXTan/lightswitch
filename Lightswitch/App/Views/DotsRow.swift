import SwiftUI
import LightswitchKit

/// One wing of the island: the dots for its slots, nearest the notch first,
/// plus a "+N" on the right wing when more sessions exist than slots. Empty
/// slots keep their space so positions never shift.
struct DotsRow: View {
    @EnvironmentObject private var store: SessionStore
    let side: IslandLayout.Side

    var body: some View {
        let slots = IslandLayout.slots(store.slotted, side: side)
        // Screen order: the right wing reads outward from the notch, the
        // left wing is mirrored so its first slot is beside the notch too.
        let indices = side == .right ? Array(slots.indices) : Array(slots.indices.reversed())
        HStack(spacing: IslandLayout.gap) {
            ForEach(indices, id: \.self) { index in
                SessionDot(session: slots[index],
                           acknowledged: slots[index].map { store.isAcknowledged($0.id) } ?? true)
                    .contentShape(Rectangle().inset(by: -5))
                    .onTapGesture {
                        if let session = slots[index] { NotchCoordinator.shared.select(session) }
                    }
            }
            if side == .right, !store.overflow.isEmpty {
                Text("+\(store.overflow.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: IslandLayout.overflowWidth, alignment: .leading)
                    .accessibilityLabel("\(store.overflow.count) more sessions")
            }
        }
        .animation(.smooth(duration: 0.25), value: slots.count)
    }
}

/// A single status dot. Red and unacknowledged: it pulses. Done and idle
/// (Claude has been waiting a while): it breathes slowly. With Reduce Motion
/// on, the red dot gets a ring instead of a pulse.
struct SessionDot: View {
    let session: Session?
    let acknowledged: Bool
    var size: CGFloat = IslandLayout.dot

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
