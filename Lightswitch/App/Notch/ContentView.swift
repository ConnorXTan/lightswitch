import SwiftUI
import LightswitchKit

/// The root view of every notch window: the black shape, its hover
/// behaviour, and the three layouts it can hold (closed, peeking, open).
struct ContentView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var coordinator: NotchCoordinator
    @EnvironmentObject private var store: SessionStore
    @AppStorage(Preferences.openOnHoverKey) private var openOnHover = true

    @State private var hovering = false
    @State private var hoverTask: Task<Void, Never>?

    /// The wing the closed shape grows to the right of the physical notch to
    /// hold the dots (the notch itself has no pixels). The closed shape is
    /// shifted right by half of it so the notch part stays exactly over the
    /// hardware.
    private var closedWing: CGFloat {
        guard vm.hasNotch else { return 0 }
        return WingLayout.wingWidth(store.slotted, overflow: store.overflow.count)
    }

    /// Where the closed shape sits relative to the container, so the hover
    /// region can follow it.
    private var closedOffset: CGFloat {
        vm.state == .closed && coordinator.peek == nil ? closedWing / 2 : 0
    }

    /// Each layout draws its own black surface, so the closed shape never
    /// morphs into the panel: the panel pops in over it, already centred on
    /// the notch, and nothing has to slide into place afterwards. Hover is
    /// tracked on this container, which outlives the layouts, so swapping
    /// them cannot fire a stray mouse-out. The state changes themselves are
    /// animated where they are made (`NotchViewModel`, `showPeek`).
    var body: some View {
        VStack(spacing: 0) {
            layout
                .contentShape(Rectangle().offset(x: closedOffset))
                .onHover(perform: handleHover)
            Spacer(minLength: 0)
        }
        .frame(width: NotchMetrics.windowSize.width,
               height: NotchMetrics.windowSize.height,
               alignment: .top)
        .onChange(of: vm.state) { _, newState in
            if newState == .closed { hovering = false }
        }
    }

    @ViewBuilder
    private var layout: some View {
        switch vm.state {
        case .open:
            OpenLayout()
                .surface(radii: NotchMetrics.openRadii, lift: 0.5)
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
        case .closed:
            if let peek = coordinator.peek {
                PeekLayout(peek: peek)
                    .surface(radii: NotchMetrics.closedRadii, lift: hovering ? 0.5 : 0)
                    .transition(.opacity)
            } else {
                ClosedLayout()
                    .surface(radii: NotchMetrics.closedRadii, lift: hovering ? 0.5 : 0)
                    .offset(x: closedWing / 2)
                    .animation(.smooth(duration: 0.3), value: closedWing)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Hover

    private func handleHover(_ isHovering: Bool) {
        hoverTask?.cancel()
        hovering = isHovering

        if isHovering {
            guard openOnHover, !vm.isOpen else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: NotchMetrics.hoverOpenDelay)
                guard !Task.isCancelled, hovering, !vm.isOpen else { return }
                vm.open()
            }
        } else {
            guard vm.isOpen else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: NotchMetrics.hoverCloseDelay)
                guard !Task.isCancelled, !hovering, vm.isOpen else { return }
                vm.close()
            }
        }
    }
}

// MARK: - Closed

/// On a notched display: the physical notch (no pixels, so nothing is drawn
/// there) plus a narrow wing on the right holding the dots two to a column.
/// On other displays the closed shape is a pill over the menu bar and the
/// dots sit centred in it.
struct ClosedLayout: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        if vm.hasNotch {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: vm.closedSize.width, height: vm.closedSize.height)
                let wing = WingLayout.wingWidth(store.slotted, overflow: store.overflow.count)
                if wing > 0 {
                    DotsGrid()
                        .frame(width: wing - WingLayout.leadingInset - WingLayout.trailingInset,
                               height: vm.closedSize.height)
                        .padding(.leading, WingLayout.leadingInset)
                        .padding(.trailing, WingLayout.trailingInset)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.toggle() }
                }
            }
        } else {
            DotsGrid()
                .frame(width: vm.closedSize.width - NotchMetrics.closedInset * 2,
                       height: vm.closedSize.height)
                .padding(.horizontal, NotchMetrics.closedInset)
                .contentShape(Rectangle())
                .onTapGesture { vm.toggle() }
        }
    }
}

// MARK: - Peek

/// The closed shape widened to show a line of text either side of the notch:
/// the folder on the left, what it wants on the right. Without a notch the
/// two sit together in a pill.
struct PeekLayout: View {
    @EnvironmentObject private var vm: NotchViewModel
    let peek: NotchCoordinator.Peek

    private var title: some View {
        Text(peek.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var detail: some View {
        Text(peek.detail)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(peek.tint)
            .lineLimit(1)
    }

    var body: some View {
        if vm.hasNotch {
            HStack(spacing: 0) {
                title.frame(maxWidth: .infinity, alignment: .trailing)
                Color.clear
                    .frame(width: vm.closedSize.width + NotchMetrics.closedInset)
                detail.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .frame(width: NotchMetrics.peekWidth, height: vm.closedSize.height)
        } else {
            HStack(spacing: 8) {
                title
                detail
            }
            .padding(.horizontal, 24)
            .frame(minWidth: vm.closedSize.width)
            .frame(height: vm.closedSize.height)
        }
    }
}

// MARK: - Open

/// The expanded panel. The header row leaves a gap the width of the physical
/// notch so nothing is drawn behind it.
struct OpenLayout: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var coordinator: NotchCoordinator

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: vm.hasNotch ? vm.closedSize.width + NotchMetrics.closedInset : 0)
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: vm.closedSize.height)

            SessionListView(hooksInstalled: coordinator.hooksInstalled,
                            onInstallHooks: { coordinator.installHooks() },
                            onSelect: { coordinator.select($0) })
        }
        .padding(.horizontal, NotchMetrics.openSideInset)
        .padding(.bottom, NotchMetrics.openInset)
        .frame(width: NotchMetrics.openWidth)
    }

    /// One short line: what needs you, else how many terminals. The project
    /// count is left out; the headers below already show it, and it does not
    /// fit beside the notch.
    private var summary: String {
        let red = store.sessions.filter { $0.state == .needsYou }.count
        if red > 0 { return red == 1 ? "1 needs you" : "\(red) need you" }
        let n = store.sessions.count
        if n == 0 { return "" }
        return n == 1 ? "1 terminal" : "\(n) terminals"
    }
}

// MARK: - Surface

private extension View {
    /// The black notch surface: background, silhouette and lift.
    func surface(radii: (top: CGFloat, bottom: CGFloat), lift: Double) -> some View {
        background(Color.black)
            .clipShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
            .shadow(color: .black.opacity(lift), radius: 14, x: 0, y: 8)
    }
}
