import SwiftUI
import LightswitchKit

/// The open notch's body: one row per session, or what to do when there
/// are none.
struct SessionListView: View {
    @EnvironmentObject private var store: SessionStore
    var hooksInstalled: Bool = true
    var onInstallHooks: () -> Void = {}
    var onSelect: (Session) -> Void = { _ in }

    private static let visibleRows = 6

    var body: some View {
        if store.sessions.isEmpty {
            EmptySessionsView(hooksInstalled: hooksInstalled, onInstallHooks: onInstallHooks)
        } else {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                let duplicates = duplicateFolders
                let rows = VStack(spacing: 1) {
                    ForEach(store.sessions) { session in
                        SessionRow(session: session,
                                   acknowledged: store.isAcknowledged(session.id),
                                   showID: duplicates.contains(session.folderName),
                                   now: context.date) {
                            onSelect(session)
                        }
                    }
                }
                if store.sessions.count > Self.visibleRows {
                    ScrollView(.vertical) { rows }
                        .frame(height: CGFloat(Self.visibleRows) * (SessionRow.height + 1))
                } else {
                    rows
                }
            }
        }
    }

    private var duplicateFolders: Set<String> {
        var seen: Set<String> = []
        var dup: Set<String> = []
        for s in store.sessions {
            if !seen.insert(s.folderName).inserted { dup.insert(s.folderName) }
        }
        return dup
    }
}

struct SessionRow: View {
    static let height: CGFloat = 32

    let session: Session
    let acknowledged: Bool
    let showID: Bool
    let now: Date
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            SessionDot(session: session, acknowledged: acknowledged)
            Text(session.folderName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            if showID {
                Text(session.shortID)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 8)
            Text(session.state.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(session.state == .idle ? .white.opacity(0.45) : session.state.color)
            Text(session.age(at: now))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(hovering ? 0.09 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.folderName) \(session.state.announcement), \(session.age(at: now))")
        .accessibilityAddTraits(.isButton)
    }
}

/// Teaches the interface: what will appear here, and the one thing that
/// might be missing for that to happen.
struct EmptySessionsView: View {
    let hooksInstalled: Bool
    let onInstallHooks: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if hooksInstalled {
                Text("No sessions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Start `claude` in a terminal and a dot appears here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Text("Hooks not installed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Sessions report their state through Claude Code hooks.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                Button(action: onInstallHooks) {
                    Text("Install hooks")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(.white.opacity(0.14)))
                .foregroundStyle(.white)
                .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.vertical, 6)
    }
}
