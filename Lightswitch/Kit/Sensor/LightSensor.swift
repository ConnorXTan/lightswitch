import Foundation
import os

/// The ambient light sensor as a button, published for the UI.
///
/// Runs a `SensorEngine` on its own thread (the live read blocks to pace
/// itself, so a dispatch queue would be the wrong tool) and forwards what
/// matters to the main actor: a status, a lux readout for Settings, and
/// `onCover` / `onUncover` for whatever the gesture is bound to.
///
/// Faults do not stop the loop. A room under `minBaselineLux` puts the
/// engine in `.fault(message)` and the thread keeps polling, so the lux
/// readout stays live and `restart()` can recalibrate once the light is on.
@MainActor
public final class LightSensor: ObservableObject {
    public enum Status: Equatable {
        /// Not running.
        case off
        /// Averaging the ambient baseline; do not shade the screen.
        case calibrating
        /// Ready: covering the sensor will fire.
        case armed
        /// The hand is there.
        case covered
        /// The detector refused to arm; the text says why.
        case fault(String)
        /// The sensor could not be opened; the text says why.
        case unavailable(String)
    }

    @Published public private(set) var status: Status = .off
    @Published public private(set) var lux: Double = 0
    @Published public private(set) var baseline: Double = 0
    @Published public private(set) var ratio: Double = 0
    @Published public private(set) var lastEvent: SensorEngine.Event?

    /// Called on the main actor when the debounced cover edge fires.
    public var onCover: (() -> Void)?
    /// Called on the main actor when the debounced release edge fires.
    public var onUncover: (() -> Void)?

    public let config: SensorEngine.Config

    private var pendingEngine: SensorEngine?
    private var thread: Thread?
    private let finished = DispatchSemaphore(value: 0)
    private let flags = OSAllocatedUnfairLock(initialState: Flags())

    private struct Flags {
        var stop = false
        var recalibrate = false
    }

    /// The live sensor, opened by `start()`.
    public init(config: SensorEngine.Config = .default) {
        self.config = config
    }

    /// Drive the sensor from an engine you already opened, such as a replay
    /// of a recorded trace. Everything else behaves exactly as live.
    public init(engine: SensorEngine) {
        self.config = engine.config
        self.pendingEngine = engine
    }

    public var isRunning: Bool { thread != nil }

    // MARK: Control

    public func start() {
        guard thread == nil else { return }

        let engine: SensorEngine
        if let pending = pendingEngine {
            engine = pending
            pendingEngine = nil
        } else {
            do {
                engine = try SensorEngine.openIOKit(config: config)
            } catch SensorEngine.Error.open(let reason) {
                status = .unavailable(reason)
                return
            } catch {
                status = .unavailable(error.localizedDescription)
                return
            }
        }

        flags.withLock { $0 = Flags() }
        status = .calibrating

        let thread = Thread { [weak self, engine] in
            self?.run(engine)
            self?.finished.signal()
        }
        thread.name = "lightswitch.sensor"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    /// Stops polling and waits for the thread to exit. Returns within one
    /// poll period for the live sensor (the read paces itself), sooner for
    /// a replay.
    public func stop() {
        guard thread != nil else { return }
        flags.withLock { $0.stop = true }
        _ = finished.wait(timeout: .now() + 2)
        thread = nil
        status = .off
        lastEvent = nil
    }

    /// Recalibrate: the way back from `.fault` once the room is lit, or a
    /// fresh baseline after the light changed a lot. Starts if stopped.
    public func restart() {
        if thread == nil {
            start()
        } else {
            flags.withLock { $0.recalibrate = true }
            status = .calibrating
        }
    }

    // MARK: The loop (sensor thread)

    private nonisolated func run(_ engine: SensorEngine) {
        var lastPublishedLux = -1.0
        var lastPublishedState: SensorEngine.State?
        var lastPublishTime = Date.distantPast

        while true {
            let flags = self.flags.withLock { f -> Flags in
                let copy = f
                f.recalibrate = false
                return copy
            }
            if flags.stop { break }
            if flags.recalibrate {
                engine.recalibrate()
                lastPublishedState = nil
            }

            guard let sample = engine.step() else {
                // Stream ended (a replay ran out, or the read failed).
                publish(status: .off, sample: nil, event: nil)
                return
            }
            if sample.lux < 0 { continue } // dropped read; nothing new to say

            let now = Date()
            let stateChanged = sample.state != lastPublishedState
            let luxMoved = lastPublishedLux < 0
                || abs(sample.lux - lastPublishedLux) > max(1, lastPublishedLux * 0.01)
            let dueForReadout = now.timeIntervalSince(lastPublishTime) >= 0.1

            guard sample.event != nil || stateChanged || (luxMoved && dueForReadout) else { continue }

            let status: Status
            switch sample.state {
            case .calibrating: status = .calibrating
            case .covered: status = .covered
            case .idle, .tapPending, .spent: status = .armed
            case .fault: status = .fault(engine.fault ?? "sensor fault")
            }
            publish(status: status, sample: sample, event: sample.event)

            lastPublishedLux = sample.lux
            lastPublishedState = sample.state
            lastPublishTime = now
        }
    }

    private nonisolated func publish(status: Status, sample: SensorEngine.Sample?,
                                     event: SensorEngine.Event?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.status = status
            if let sample {
                self.lux = sample.lux
                self.baseline = sample.baseline
                self.ratio = sample.ratio
            }
            if let event {
                self.lastEvent = event
                switch event {
                case .cover: self.onCover?()
                case .uncover: self.onUncover?()
                }
            }
        }
    }
}
