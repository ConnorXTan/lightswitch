import SwiftUI
import LightswitchKit

/// The open notch's body: each project with its Claude terminals under it,
/// or what to do when there are none.
struct SessionListView: View {
    @EnvironmentObject private var store: SessionStore
    var hooksInstalled: Bool = true
    var onInstallHooks: () -> Void = {}
    var onSelect: (Session) -> Void = { _ in }

    /// Rows (headers and terminals) shown before the list scrolls.
    private static let visibleRows = 9
    private static let maxHeight: CGFloat = 262

    var body: some View {
        if store.sessions.isEmpty {
            EmptySessionsView(hooksInstalled: hooksInstalled, onInstallHooks: onInstallHooks)
        } else {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                let groups = store.groups
                let duplicates = duplicateNames(groups)
                let list = VStack(alignment: .leading, spacing: 6) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 1) {
                            ProjectHeader(group: group, showLocation: duplicates.contains(group.name))
                            ForEach(group.sessions) { session in
                                SessionRow(session: session,
                                           subpath: group.subpath(of: session),
                                           acknowledged: store.isAcknowledged(session.id),
                                           now: context.date) {
                                    onSelect(session)
                                }
                            }
                        }
                    }
                }
                if groups.count + store.sessions.count > Self.visibleRows {
                    ScrollView(.vertical) { list }
                        .frame(height: Self.maxHeight)
                } else {
                    list
                }
            }
        }
    }

    private func duplicateNames(_ groups: [ProjectGroup]) -> Set<String> {
        var seen: Set<String> = []
        var dup: Set<String> = []
        for g in groups {
            if !seen.insert(g.name).inserted { dup.insert(g.name) }
        }
        return dup
    }
}

/// The project line: folder name, and where it lives when two projects
/// share a name.
struct ProjectHeader: View {
    let group: ProjectGroup
    let showLocation: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(group.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            if showLocation {
                Text(group.location)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            Text(group.sessions.count == 1 ? "1 terminal" : "\(group.sessions.count) terminals")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .accessibilityElement(children: .combine)
    }
}

/// One Claude terminal inside a project: the session's name (or, before it
/// has one, which terminal it is in), with the subfolder or worktree it
/// sits in when that is not the project root.
struct SessionRow: View {
    static let height: CGFloat = 28

    let session: Session
    var subpath: String = ""
    let acknowledged: Bool
    let now: Date
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            SessionDot(session: session, acknowledged: acknowledged)
            Text(session.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(session.title.isEmpty ? .middle : .tail)
                .layoutPriority(1)
                .help(session.terminalLabel)
            if !subpath.isEmpty {
                Text(subpath)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            // The state word and age never give way: a long name truncates.
            Text(session.state.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(session.state == .idle ? .white.opacity(0.45) : session.state.color)
                .fixedSize()
                .layoutPriority(2)
            Text(session.age(at: now))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.leading, 22)
        .padding(.trailing, 10)
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
        .accessibilityLabel("\(session.projectName)\(subpath.isEmpty ? "" : " " + subpath), \(session.terminalLabel), \(session.state.announcement), \(session.age(at: now))")
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
