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
    @State private var openTask: Task<Void, Never>?
    @State private var closeTask: Task<Void, Never>?
    @State private var watchdog: Task<Void, Never>?
    /// The visible shape's size and window, to check the real pointer
    /// position. Hover events are only a prompt: whenever the view tree
    /// changes under a still pointer SwiftUI fires a stray mouse-out, and no
    /// mouse-in follows until something else changes. So opening and closing
    /// are decided by where the pointer actually is.
    @State private var shapeSize: CGSize = .zero
    /// The open panel's last measured height, so the panel's region is
    /// known before it has opened.
    @State private var openHeight: CGFloat = NotchMetrics.windowSize.height
    @State private var windowHandle = WindowHandle()

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

    /// Each layout draws its own black surface. The panel and the peek grow
    /// out of the closed box through `Reveal`: an animated clip from the
    /// closed silhouette (notch plus wing) to their full outline, in one
    /// motion, content revealed by the clip. The closed layout sits above
    /// them: its dots fade out quickly as the box starts to grow, and fade
    /// back in as the box finishes shrinking. Hover is tracked on this
    /// container, which outlives
    /// the layouts, so swapping them cannot fire a stray mouse-out. The state
    /// changes themselves are animated where they are made (`NotchViewModel`,
    /// `showPeek`).
    var body: some View {
        VStack(spacing: 0) {
            layout
                .contentShape(Rectangle().offset(x: closedOffset))
                .onHover(perform: handleHover)
                .background(GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) { _, size in
                        shapeSize = size
                        if vm.isOpen, size.height > vm.closedSize.height { openHeight = size.height }
                    }
                })
            Spacer(minLength: 0)
        }
        .frame(width: NotchMetrics.windowSize.width,
               height: NotchMetrics.windowSize.height,
               alignment: .top)
        .background(WindowReader(handle: windowHandle))
        .onChange(of: vm.state) { _, newState in
            if newState == .closed {
                hovering = false
                watchdog?.cancel()
                watchdog = nil
            }
        }
    }

    /// Whether the pointer is over the visible shape right now, from its
    /// real position rather than the last hover event. With `expanded`,
    /// the region is the open panel's whether or not it is open yet: from
    /// the first hover the panel's whole area counts, so a hand that moves
    /// down into it before the delay is up is not treated as leaving.
    private func pointerInsideShape(expanded: Bool = false) -> Bool {
        // The window's frame, or where it would be: the window is centred on
        // the notch at the top of its screen.
        let frame: CGRect
        if let window = windowHandle.window {
            frame = window.frame
        } else if let screen = vm.screen {
            let size = NotchMetrics.windowSize
            frame = CGRect(x: NotchGeometry.notchCenterX(for: screen) - size.width / 2,
                           y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        } else {
            return false
        }
        var size = shapeSize
        var offset = closedOffset
        if expanded && !vm.isOpen {
            size = CGSize(width: NotchMetrics.openWidth, height: openHeight)
            offset = 0
        } else if size == .zero {
            // No measurement yet: the layout's known size.
            if vm.isOpen {
                size = CGSize(width: NotchMetrics.openWidth, height: NotchMetrics.windowSize.height)
            } else if coordinator.peek != nil {
                size = CGSize(width: NotchMetrics.peekWidth, height: vm.closedSize.height)
            } else {
                size = CGSize(width: vm.closedSize.width + closedWing, height: vm.closedSize.height)
            }
        }
        let x = frame.minX + (frame.width - size.width) / 2 + offset
        let rect = CGRect(x: x, y: frame.maxY - size.height, width: size.width, height: size.height)
        return rect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    @ViewBuilder
    private var layout: some View {
        switch vm.state {
        case .open:
            OpenLayout()
                .surface(radii: NotchMetrics.openRadii)
                .transition(Reveal.transition(closed: vm.closedSize, wing: closedWing, lift: 0.5))
                .zIndex(1)
        case .closed:
            if let peek = coordinator.peek {
                PeekLayout(peek: peek)
                    .surface(radii: NotchMetrics.closedRadii)
                    .transition(Reveal.transition(closed: vm.closedSize, wing: closedWing, lift: 0))
                    .zIndex(1)
            } else {
                ClosedLayout()
                    .surface(radii: NotchMetrics.closedRadii)
                    .shadow(color: .black.opacity(hovering ? 0.5 : 0), radius: 14, x: 0, y: 8)
                    .offset(x: closedWing / 2)
                    .animation(.smooth(duration: 0.3), value: closedWing)
                    // Above the growing box: the dots fade out as it starts to
                    // grow, and fade back in as it finishes shrinking.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.linear(duration: 0.1).delay(0.35)),
                        removal: .opacity.animation(.linear(duration: 0.12))))
                    .zIndex(2)
            }
        }
    }

    // MARK: Hover

    private func handleHover(_ isHovering: Bool) {
        Log.note(Log.app, "hover \(isHovering ? "in" : "out") open=\(vm.isOpen)")
        hovering = isHovering

        if isHovering {
            closeTask?.cancel()
            closeTask = nil
            guard openOnHover, !vm.isOpen, openTask == nil else { return }
            openTask = Task { @MainActor in
                try? await Task.sleep(for: NotchMetrics.hoverOpenDelay)
                openTask = nil
                guard !Task.isCancelled, !vm.isOpen, pointerInsideShape(expanded: true) else { return }
                vm.open()
                startWatchdog()
            }
        } else {
            // While closed a mouse-out is not trusted: the pending open looks
            // at the pointer itself when its delay is up.
            guard vm.isOpen, closeTask == nil else { return }
            closeTask = Task { @MainActor in
                try? await Task.sleep(for: NotchMetrics.hoverCloseDelay)
                closeTask = nil
                guard !Task.isCancelled, vm.isOpen else { return }
                if pointerInsideShape() {
                    Log.note(Log.app, "hover out ignored: pointer still over the shape")
                    hovering = true
                    return
                }
                vm.close()
            }
        }
    }

    /// Hover opened the panel, so hover must be able to close it even when
    /// the mouse-out never arrives: while it is open, look at the pointer
    /// now and then. A panel opened by a click or the gesture is not polled;
    /// it stays until the pointer visits and leaves, as before.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor in
            while !Task.isCancelled, vm.isOpen {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, vm.isOpen else { break }
                if !pointerInsideShape() {
                    Log.note(Log.app, "watchdog: pointer is off the panel, closing")
                    vm.close()
                    break
                }
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
    /// The black notch surface: background and silhouette.
    func surface(radii: (top: CGFloat, bottom: CGFloat)) -> some View {
        background(Color.black)
            .clipShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
    }
}
