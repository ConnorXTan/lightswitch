import CLightswitch
import Foundation

/// One light sensor plus one gesture detector, wrapped for Swift.
///
/// This is the C engine from `src/`, not a port of it: the same
/// `ls_sensor_read` → `ls_detector_push` loop the CLI runs, in switch mode,
/// so cover and release edges arrive as events about 300 ms after the hand
/// (the debounce limit measured in `docs/SIGNAL.md`). The class is not
/// thread-safe; one thread owns it at a time. `LightSensor` gives it that
/// thread and publishes to the main actor.
public final class SensorEngine {
    public enum Error: Swift.Error, Equatable {
        /// The sensor could not be opened; the text is the C engine's reason.
        case open(String)
    }

    /// Cover and release, the two edges the switch-mode detector emits.
    public enum Event: Equatable {
        case cover
        case uncover
    }

    /// The detector's state machine, mirrored from `ls_state`.
    public enum State: Equatable {
        case calibrating
        case idle
        case covered
        case tapPending
        case spent
        case fault

        init(_ s: ls_state) {
            switch s {
            case LS_STATE_CALIBRATING: self = .calibrating
            case LS_STATE_IDLE: self = .idle
            case LS_STATE_COVERED: self = .covered
            case LS_STATE_TAP_PENDING: self = .tapPending
            case LS_STATE_SPENT: self = .spent
            default: self = .fault
            }
        }
    }

    /// What one poll produced. `lux` is negative for a dropped sensor read;
    /// the detector holds its timers across those and `event` is nil.
    public struct Sample: Equatable {
        public var timeMs: Double
        public var lux: Double
        public var baseline: Double
        public var ratio: Double
        public var state: State
        public var event: Event?
    }

    /// Detector tuning, mirroring `ls_detector_config`. Switch mode is always
    /// on in this engine; it is the engine's contract, not a setting.
    public struct Config: Equatable {
        public var calibrationMs: Double
        public var minBaselineLux: Double
        public var coverRatio: Double
        public var uncoverRatio: Double
        public var debounceSamples: Int
        public var holdMs: Double
        public var doubleGapMs: Double
        public var refractoryMs: Double
        public var baselineAlpha: Double
        /// How often the live sensor is polled. 100 ms is what the measured
        /// 3-sample debounce assumes; see `docs/SIGNAL.md`.
        public var pollMs: Double

        /// The C engine's defaults, the ones every measurement was made with.
        public static let `default`: Config = {
            var c = ls_detector_config()
            ls_detector_config_defaults(&c)
            return Config(calibrationMs: c.calibration_ms,
                          minBaselineLux: c.min_baseline_lux,
                          coverRatio: c.cover_ratio,
                          uncoverRatio: c.uncover_ratio,
                          debounceSamples: Int(c.debounce_samples),
                          holdMs: c.hold_ms,
                          doubleGapMs: c.double_gap_ms,
                          refractoryMs: c.refractory_ms,
                          baselineAlpha: c.baseline_alpha,
                          pollMs: 100)
        }()

        public init(calibrationMs: Double, minBaselineLux: Double, coverRatio: Double,
                    uncoverRatio: Double, debounceSamples: Int, holdMs: Double,
                    doubleGapMs: Double, refractoryMs: Double, baselineAlpha: Double,
                    pollMs: Double) {
            self.calibrationMs = calibrationMs
            self.minBaselineLux = minBaselineLux
            self.coverRatio = coverRatio
            self.uncoverRatio = uncoverRatio
            self.debounceSamples = debounceSamples
            self.holdMs = holdMs
            self.doubleGapMs = doubleGapMs
            self.refractoryMs = refractoryMs
            self.baselineAlpha = baselineAlpha
            self.pollMs = pollMs
        }

        var cValue: ls_detector_config {
            var c = ls_detector_config()
            c.calibration_ms = calibrationMs
            c.min_baseline_lux = minBaselineLux
            c.cover_ratio = coverRatio
            c.uncover_ratio = uncoverRatio
            c.debounce_samples = Int32(debounceSamples)
            c.hold_ms = holdMs
            c.double_gap_ms = doubleGapMs
            c.refractory_ms = refractoryMs
            c.baseline_alpha = baselineAlpha
            c.switch_mode = 1
            return c
        }
    }

    public let config: Config
    /// "iokit" or "replay", from the C backend.
    public let kind: String

    private var sensor: UnsafeMutablePointer<ls_sensor>?
    private var detector = ls_detector()

    private init(sensor: UnsafeMutablePointer<ls_sensor>, config: Config) {
        self.sensor = sensor
        self.config = config
        self.kind = String(cString: ls_sensor_kind(sensor))
        var c = config.cValue
        ls_detector_init(&detector, &c)
    }

    deinit {
        close()
    }

    // MARK: Opening

    /// The live ambient light sensor, through IOKit. Fails on machines
    /// without one, and on macOS versions where the private symbols moved.
    public static func openIOKit(config: Config = .default) throws -> SensorEngine {
        var err = [CChar](repeating: 0, count: 256)
        guard let s = ls_sensor_open_iokit(config.pollMs, &err, err.count) else {
            throw Error.open(String(cString: err))
        }
        return SensorEngine(sensor: s, config: config)
    }

    /// A recorded trace (`tests/traces/*.lstrace`). With `realtime` the reads
    /// sleep to match the recording; otherwise they run as fast as the file.
    public static func openReplay(path: String, realtime: Bool,
                                  config: Config = .default) throws -> SensorEngine {
        var err = [CChar](repeating: 0, count: 256)
        guard let s = ls_sensor_open_replay(path, realtime ? 1 : 0, &err, err.count) else {
            throw Error.open(String(cString: err))
        }
        return SensorEngine(sensor: s, config: config)
    }

    // MARK: Running

    /// One poll: reads a sample (blocking to pace the live sensor) and feeds
    /// it to the detector. Returns nil when the stream ends (a replay ran
    /// out) or the read failed; the engine is closed at that point.
    public func step() -> Sample? {
        guard let sensor else { return nil }
        var t = 0.0
        var lux = 0.0
        let rc = ls_sensor_read(sensor, &t, &lux)
        guard rc > 0 else {
            close()
            return nil
        }

        let gesture = ls_detector_push(&detector, t, lux)
        let event: Event?
        switch gesture {
        case LS_GESTURE_ON: event = .cover
        case LS_GESTURE_OFF: event = .uncover
        default: event = nil
        }

        return Sample(timeMs: t,
                      lux: lux,
                      baseline: ls_detector_baseline(&detector),
                      ratio: ls_detector_ratio(&detector),
                      state: State(ls_detector_state(&detector)),
                      event: event)
    }

    /// The detector's reason for refusing to run, once it has faulted
    /// (a room under `minBaselineLux`); nil otherwise.
    public var fault: String? {
        guard ls_detector_state(&detector) == LS_STATE_FAULT else { return nil }
        return String(cString: ls_detector_fault(&detector))
    }

    public var state: State { State(ls_detector_state(&detector)) }

    /// Forget the baseline and calibrate again from the next samples. The way
    /// out of a fault once the room has been lit.
    public func recalibrate() {
        var c = config.cValue
        ls_detector_init(&detector, &c)
    }

    /// Whether the underlying sensor is still open.
    public var isOpen: Bool { sensor != nil }

    private func close() {
        if let sensor {
            ls_sensor_close(sensor)
            self.sensor = nil
        }
    }
}
