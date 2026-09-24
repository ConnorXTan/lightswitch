import Combine
import XCTest
@testable import LightswitchKit

/// The Swift bridge over the C detector, proven with the same recorded
/// fixtures the C suite uses. The detector's own behaviour is pinned by
/// `tests/test_detector.c`; these tests pin that the bridge relays it.
final class SensorEngineTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // Lightswitch
        .deletingLastPathComponent()   // repo

    static func trace(_ name: String) -> String {
        repoRoot.appendingPathComponent("tests/traces/\(name).lstrace").path
    }

    struct Run {
        var events: [SensorEngine.Event] = []
        var samples = 0
        var finalState: SensorEngine.State = .calibrating
        var fault: String?
    }

    func replay(_ name: String) throws -> Run {
        let engine = try SensorEngine.openReplay(path: Self.trace(name), realtime: false)
        XCTAssertEqual(engine.kind, "replay")
        var run = Run()
        while let sample = engine.step() {
            run.samples += 1
            if let e = sample.event { run.events.append(e) }
            run.finalState = sample.state
        }
        run.fault = engine.fault
        XCTAssertFalse(engine.isOpen, "engine closes itself at end of stream")
        return run
    }

    // MARK: SensorEngine

    func testHoldIsOneCoverAndOneRelease() throws {
        let run = try replay("hold")
        XCTAssertEqual(run.events, [.cover, .uncover])
        XCTAssertGreaterThan(run.samples, 20)
        XCTAssertEqual(run.finalState, .idle)
        XCTAssertNil(run.fault)
    }

    func testTapIsOneCoverAndOneRelease() throws {
        XCTAssertEqual(try replay("tap").events, [.cover, .uncover])
    }

    func testIdleRoomProducesNothing() throws {
        let run = try replay("idle")
        XCTAssertEqual(run.events, [])
        XCTAssertEqual(run.finalState, .idle)
    }

    func testSomeoneWalkingPastProducesNothing() throws {
        XCTAssertEqual(try replay("walk_past").events, [])
    }

    func testSlowDriftProducesNothing() throws {
        XCTAssertEqual(try replay("drift").events, [])
    }

    func testDarkRoomFaultsWithAReason() throws {
        let run = try replay("dark")
        XCTAssertEqual(run.events, [])
        XCTAssertEqual(run.finalState, .fault)
        let fault = try XCTUnwrap(run.fault)
        XCTAssertFalse(fault.isEmpty)
        XCTAssertTrue(fault.contains("lux"), fault)
    }

    func testRecalibrateClearsAFault() throws {
        let engine = try SensorEngine.openReplay(path: Self.trace("dark"), realtime: false)
        while let s = engine.step(), s.state != .fault {}
        XCTAssertEqual(engine.state, .fault)
        engine.recalibrate()
        XCTAssertEqual(engine.state, .calibrating)
        XCTAssertNil(engine.fault)
    }

    func testMissingTraceThrowsOpen() {
        XCTAssertThrowsError(try SensorEngine.openReplay(path: Self.trace("does_not_exist"),
                                                         realtime: false)) { error in
            guard case SensorEngine.Error.open(let reason) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testDefaultConfigMatchesTheCEngine() {
        let c = SensorEngine.Config.default
        XCTAssertEqual(c.coverRatio, 0.45)
        XCTAssertEqual(c.uncoverRatio, 0.75)
        XCTAssertEqual(c.debounceSamples, 3)
        XCTAssertEqual(c.minBaselineLux, 25)
        XCTAssertEqual(c.pollMs, 100)
        XCTAssertEqual(c.cValue.switch_mode, 1)
    }

    // MARK: LightSensor

    @MainActor
    func testLightSensorDeliversCoverThenUncoverOnMain() throws {
        let engine = try SensorEngine.openReplay(path: Self.trace("hold"), realtime: false)
        let sensor = LightSensor(engine: engine)

        let covered = expectation(description: "cover")
        let uncovered = expectation(description: "uncover")
        var order: [SensorEngine.Event] = []
        sensor.onCover = {
            XCTAssertTrue(Thread.isMainThread)
            order.append(.cover)
            covered.fulfill()
        }
        sensor.onUncover = {
            XCTAssertTrue(Thread.isMainThread)
            order.append(.uncover)
            uncovered.fulfill()
        }

        XCTAssertEqual(sensor.status, .off)
        sensor.start()
        XCTAssertTrue(sensor.isRunning)
        wait(for: [covered, uncovered], timeout: 10, enforceOrder: true)
        XCTAssertEqual(order, [.cover, .uncover])
        XCTAssertGreaterThan(sensor.baseline, 1000, "baseline was published")

        let t0 = Date()
        sensor.stop()
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5)
        XCTAssertFalse(sensor.isRunning)
        XCTAssertEqual(sensor.status, .off)
    }

    @MainActor
    func testLightSensorReportsADarkRoomAsFault() throws {
        let engine = try SensorEngine.openReplay(path: Self.trace("dark"), realtime: false)
        let sensor = LightSensor(engine: engine)

        let faulted = expectation(description: "fault published")
        faulted.assertForOverFulfill = false
        let cancellable = sensor.$status.sink { status in
            if case .fault(let reason) = status, reason.contains("lux") { faulted.fulfill() }
        }
        sensor.start()
        wait(for: [faulted], timeout: 10)
        cancellable.cancel()
        sensor.stop()
    }

    @MainActor
    func testLightSensorStopIsIdempotent() {
        let sensor = LightSensor()
        sensor.stop()
        sensor.stop()
        XCTAssertEqual(sensor.status, .off)
    }
}
