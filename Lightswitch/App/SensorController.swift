import AppKit
import Combine
import Foundation
import LightswitchKit
import CLightswitch

/// Runs the light sensor when the setting is on and turns a cover gesture
/// into whatever the user chose. Also the place Settings reads the live
/// readout from.
@MainActor
final class SensorController: ObservableObject {
    static let shared = SensorController()

    let sensor = LightSensor()
    /// The last problem running an action (Accessibility permission, mostly).
    @Published private(set) var lastActionError: String?

    private var cancellables: Set<AnyCancellable> = []
    private var observer: NSObjectProtocol?

    private init() {
        sensor.onCover = { [weak self] in self?.covered() }
        sensor.$status
            .removeDuplicates()
            .sink { status in Log.note(Log.sensor, "sensor \(status)") }
            .store(in: &cancellables)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
    }

    /// Starts or stops the sensor to match the setting. Safe to call often.
    func apply() {
        if Preferences.sensorEnabled {
            if !sensor.isRunning { sensor.start() }
        } else if sensor.isRunning {
            sensor.stop()
        }
    }

    func recalibrate() {
        sensor.restart()
    }

    // MARK: Gesture

    private func covered() {
        let coordinator = NotchCoordinator.shared
        let store = SessionStore.shared
        let action = Preferences.gestureAction
        Log.note(Log.sensor, "cover → \(action.rawValue)")

        switch action {
        case .smart:
            if let session = store.needingAttention.first {
                coordinator.hidePeek()
                coordinator.select(session)
            } else {
                coordinator.toggleAll()
            }
        case .toggleNotch:
            coordinator.toggleAll()
        case .acknowledge:
            for session in store.needingAttention { store.acknowledge(session.id) }
            coordinator.hidePeek()
        case .playPause, .closeWindow:
            if let spec = action.actionSpec { run(spec) }
        case .none:
            break
        }
    }

    /// Runs a `key:` or `media:` spec through the C engine, the same code the
    /// CLI uses.
    private func run(_ spec: String) {
        var action = ls_action()
        var err = [CChar](repeating: 0, count: 256)
        if ls_action_parse(spec, &action, &err, err.count) != 0 || ls_action_run(&action, &err, err.count) != 0 {
            lastActionError = String(cString: err)
            Log.note(Log.sensor, "action failed: \(lastActionError ?? "")")
        } else {
            lastActionError = nil
        }
    }
}
