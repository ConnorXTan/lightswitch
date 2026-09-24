import SwiftUI
import LightswitchKit

/// The root view of every notch window: the black shape, its hover
/// behaviour, and the three layouts it can hold (closed, peeking, open).
struct ContentView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var coordinator: NotchCoordinator
    @AppStorage(Preferences.openOnHoverKey) private var openOnHover = true

    @State private var hovering = false
    @State private var hoverTask: Task<Void, Never>?

    private var shape: NotchShape {
        NotchShape(topRadius: vm.isOpen ? NotchMetrics.openRadii.top : NotchMetrics.closedRadii.top,
                   bottomRadius: vm.isOpen ? NotchMetrics.openRadii.bottom : NotchMetrics.closedRadii.bottom)
    }

    var body: some View {
        VStack(spacing: 0) {
            layout
                .background(Color.black)
                .clipShape(shape)
                .shadow(color: .black.opacity(vm.isOpen || hovering ? 0.5 : 0),
                        radius: 14, x: 0, y: 8)
                .contentShape(Rectangle())
                .onHover(perform: handleHover)
                .animation(vm.isOpen ? NotchMetrics.openAnimation : NotchMetrics.closeAnimation,
                           value: vm.state)
                .animation(NotchMetrics.peekAnimation, value: coordinator.peek)
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

/// Exactly the physical notch, black on black. Its content sits inside a
/// 10 pt inset on each side.
struct ClosedLayout: View {
    @EnvironmentObject private var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Phase 2 places the session dots here.
            Color.clear
        }
        .frame(width: vm.closedSize.width - NotchMetrics.closedInset * 2,
               height: vm.closedSize.height)
        .padding(.horizontal, NotchMetrics.closedInset)
    }
}

// MARK: - Peek

/// The closed shape widened to show a line of text either side of the notch.
struct PeekLayout: View {
    @EnvironmentObject private var vm: NotchViewModel
    let peek: NotchCoordinator.Peek

    var body: some View {
        HStack(spacing: 0) {
            Text(peek.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear
                .frame(width: vm.closedSize.width + NotchMetrics.closedInset)
            Text(peek.detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(peek.tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .frame(width: NotchMetrics.peekWidth, height: vm.closedSize.height)
    }
}

// MARK: - Open

/// The expanded panel. The header row leaves a gap the width of the physical
/// notch so nothing is drawn behind it.
struct OpenLayout: View {
    @EnvironmentObject private var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: vm.closedSize.width + NotchMetrics.closedInset)
                Color.clear
                    .frame(maxWidth: .infinity)
            }
            .frame(height: vm.closedSize.height)

            // Phase 2 replaces this with the session list.
            Text("No sessions")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, NotchMetrics.openInset)
        .padding(.bottom, NotchMetrics.openInset)
        .frame(width: NotchMetrics.openWidth)
    }
}
