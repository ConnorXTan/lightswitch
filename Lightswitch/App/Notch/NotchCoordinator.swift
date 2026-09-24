import AppKit
import Combine
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
    private var cancellables: Set<AnyCancellable> = []

    /// Wired by the app: focus the terminal that owns a session.
    var selectSession: (Session) -> Void = { _ in }
    private init() {
        HooksModel.shared.$status
            .map { $0 == .installed }
            .removeDuplicates()
            .assign(to: &$hooksInstalled)
    }

    func select(_ session: Session) {
        SessionStore.shared.acknowledge(session.id)
        selectSession(session)
    }

    func installHooks() { HooksModel.shared.install() }

    // MARK: Alerts

    /// Reacts to sessions turning red: a peek beside the notch (unless a
    /// notch is already open and showing the list) and, if enabled, a sound.
    func bind(to store: SessionStore) {
        store.$alert
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] alert in self?.announce(alert) }
            .store(in: &cancellables)
    }

    private func announce(_ alert: SessionStore.Alert) {
        if Preferences.alertSound {
            NSSound(named: "Glass")?.play()
        }
        guard !anyOpen else { return }
        showPeek(Peek(title: alert.session.projectName,
                      detail: alert.session.state.label,
                      tint: alert.session.state.color),
                 for: .seconds(3))
    }

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
