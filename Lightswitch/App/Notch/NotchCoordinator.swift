import SwiftUI
import LightswitchKit

/// The one object that knows about every notch window. It carries the
/// transient "peek" shown beside the closed notch and lets non-view code
/// (the light sensor, the menu) open or close every display at once.
@MainActor
final class NotchCoordinator: ObservableObject {
    static let shared = NotchCoordinator()

    /// Text shown beside the closed notch for a few seconds.
    struct Peek: Equatable {
        var title: String
        var detail: String
        var tint: Color = .white
    }

    @Published private(set) var peek: Peek?
    /// Whether the Claude Code hooks are installed; drives the empty state.
    @Published var hooksInstalled = true
    private var peekTask: Task<Void, Never>?
    private var viewModels: [String: NotchViewModel] = [:]

    /// Wired by the app: focus the terminal that owns a session.
    var selectSession: (Session) -> Void = { _ in }
    /// Wired by the app once the installer exists.
    var installHooksAction: () -> Void = {}

    private init() {}

    func select(_ session: Session) {
        SessionStore.shared.acknowledge(session.id)
        selectSession(session)
    }

    func installHooks() { installHooksAction() }

    // MARK: Windows

    func register(_ vm: NotchViewModel, screenUUID: String) {
        viewModels[screenUUID] = vm
    }

    func unregister(screenUUID: String) {
        viewModels[screenUUID] = nil
    }

    func viewModel(for screenUUID: String) -> NotchViewModel? {
        viewModels[screenUUID]
    }

    var anyOpen: Bool { viewModels.values.contains { $0.isOpen } }

    func openAll() {
        viewModels.values.forEach { $0.open() }
    }

    func closeAll() {
        viewModels.values.forEach { $0.close() }
    }

    func toggleAll() {
        anyOpen ? closeAll() : openAll()
    }

    // MARK: Peek

    func showPeek(_ new: Peek, for duration: Duration = .seconds(3)) {
        peekTask?.cancel()
        withAnimation(NotchMetrics.peekAnimation) { peek = new }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hidePeek()
        }
    }

    func hidePeek() {
        peekTask?.cancel()
        peekTask = nil
        withAnimation(NotchMetrics.peekAnimation) { peek = nil }
    }
}
