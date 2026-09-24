import SwiftUI
import LightswitchKit

/// The root view of every notch window: the black island, its hover
/// behaviour, and the three layouts it can hold (closed, peeking, open).
struct ContentView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var coordinator: NotchCoordinator
    @EnvironmentObject private var store: SessionStore
    @AppStorage(Preferences.openOnHoverKey) private var openOnHover = true

    @State private var hovering = false
    @State private var hoverTask: Task<Void, Never>?

    /// Closed, the island is a capsule; open, a panel.
    private var radius: CGFloat {
        vm.isOpen ? NotchMetrics.openRadius : vm.islandHeight / 2
    }

    /// The closed island grows a wing either side of the physical notch to
    /// hold the dots (the notch itself has no pixels). Both wings share one
    /// width, so the island stays centred on the notch.
    private var wingWidth: CGFloat {
        guard vm.state == .closed, coordinator.peek == nil, vm.hasNotch else { return 0 }
        return IslandLayout.wingWidth(store.slotted, overflow: store.overflow.count)
    }

    /// Nothing but the notch is showing: no island to cast a shadow.
    private var bare: Bool {
        vm.state == .closed && coordinator.peek == nil && vm.hasNotch && wingWidth == 0
    }

    var body: some View {
        VStack(spacing: 0) {
            layout
                .background(Color.black)
                .clipShape(IslandShape(radius: radius))
                .shadow(color: .black.opacity(vm.isOpen || hovering ? 0.5 : (bare ? 0 : 0.3)),
                        radius: vm.isOpen ? 14 : 6, x: 0, y: vm.isOpen ? 8 : 3)
                .contentShape(Rectangle())
                .onHover(perform: handleHover)
                .animation(vm.isOpen ? NotchMetrics.openAnimation : NotchMetrics.closeAnimation,
                           value: vm.state)
                .animation(NotchMetrics.peekAnimation, value: coordinator.peek)
                .animation(.smooth(duration: 0.3), value: wingWidth)
            Spacer(minLength: 0)
        }
        .padding(.top, vm.hasNotch ? IslandLayout.topGap : 0)
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
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
        case .closed:
            if let peek = coordinator.peek {
                PeekLayout(peek: peek)
                    .transition(.opacity)
            } else {
                ClosedLayout()
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

/// On a notched display: a wing of dots either side of the physical notch
/// (no pixels, so nothing is drawn there), the two wings the same width so
/// the island is centred. On other displays the closed shape is a pill over
/// the menu bar and the dots sit centred in it.
struct ClosedLayout: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        if vm.hasNotch {
            let wing = IslandLayout.wingWidth(store.slotted, overflow: store.overflow.count)
            HStack(spacing: 0) {
                self.wing(.left, width: wing)
                Color.clear
                    .frame(width: vm.closedSize.width, height: vm.islandHeight)
                self.wing(.right, width: wing)
            }
        } else {
            HStack(spacing: IslandLayout.gap) {
                DotsRow(side: .right)
                DotsRow(side: .left)
            }
            .frame(width: vm.closedSize.width - NotchMetrics.closedInset * 2,
                   height: vm.closedSize.height)
            .padding(.horizontal, NotchMetrics.closedInset)
            .contentShape(Rectangle())
            .onTapGesture { vm.toggle() }
        }
    }

    /// One wing: its dots hug the notch, the far end is the capsule's end.
    @ViewBuilder
    private func wing(_ side: IslandLayout.Side, width: CGFloat) -> some View {
        if width > 0 {
            let inner = IslandLayout.innerInset
            let outer = IslandLayout.outerInset
            DotsRow(side: side)
                .frame(width: width - inner - outer, height: vm.islandHeight,
                       alignment: side == .right ? .leading : .trailing)
                .padding(.leading, side == .right ? inner : outer)
                .padding(.trailing, side == .right ? outer : inner)
                .contentShape(Rectangle())
                .onTapGesture { vm.toggle() }
        }
    }
}

// MARK: - Peek

/// The island widened to show a line of text either side of the notch: the
/// project on the left, what it wants on the right. Without a notch the two
/// sit together in a pill.
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
            .frame(width: NotchMetrics.peekWidth, height: vm.islandHeight)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: vm.hasNotch ? vm.closedSize.width + NotchMetrics.closedInset : 0)
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: vm.islandHeight)

            SessionListView(hooksInstalled: coordinator.hooksInstalled,
                            onInstallHooks: { coordinator.installHooks() },
                            onSelect: { coordinator.select($0) })
        }
        .padding(.horizontal, NotchMetrics.openInset)
        .padding(.bottom, NotchMetrics.openInset)
        .frame(width: NotchMetrics.openWidth)
    }

    private var summary: String {
        let red = store.sessions.filter { $0.state == .needsYou }.count
        if red > 0 { return red == 1 ? "1 needs you" : "\(red) need you" }
        let n = store.sessions.count
        let p = store.groups.count
        if n == 0 { return "" }
        let sessions = n == 1 ? "1 terminal" : "\(n) terminals"
        return p > 1 ? "\(sessions) · \(p) projects" : sessions
    }
}
