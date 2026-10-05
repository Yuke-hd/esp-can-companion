import XCTest
import BLETransport
import CompanionProtocol
import PresetSync
@testable import CompanionLink

/// A connection manager on a fake radio with a demo controller, driven by
/// virtual time.
@MainActor
final class Bench {
    let scheduler = ManualScheduler()
    let peripheral = BLETransport.FakeController(name: "Bench Controller")
    let radio: FakeRadio
    let demo: DemoController
    let manager: ConnectionManager

    init(demo: DemoController? = nil) {
        let demo = demo ?? DemoController()
        self.demo = demo
        radio = FakeRadio(controllers: [peripheral], scheduler: scheduler, latency: 0.05)
        demo.attach(to: radio)
        manager = ConnectionManager(radio: radio, store: InMemoryDeviceStore(), scheduler: scheduler)
        manager.start()
        scheduler.runUntilIdle()
    }

    func connect() async {
        manager.connect(to: peripheral.id)
        await settle { self.manager.state.isConnected }
    }

    /// Advances virtual time and lets tasks run until `condition` holds.
    func settle(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            scheduler.advance(by: 0.01)
            await Task.yield()
        }
        XCTFail("condition never held", file: file, line: line)
    }
}

@MainActor
final class ControllerSessionTests: XCTestCase {
    func testReadsControllerWhenLinked() async {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        XCTAssertEqual(session.phase, .offline)

        await bench.connect()
        await bench.settle { session.phase == .ready }

        XCTAssertEqual(session.deviceInfo?.firmwareVersion, "0.4.0-demo")
        XCTAssertEqual(session.configStatus?.activeSource, .known(.factory))
        guard case .summary(let summary)? = session.activeConfig else {
            return XCTFail("expected a summary, got \(String(describing: session.activeConfig))")
        }
        XCTAssertEqual(summary.actions.map(\.name), ["left_turn", "right_turn", "hazard", "rpm_fill", "red_zone", "brake"])
        XCTAssertEqual(summary.profile, .factory)
    }

    func testCustomOverrideIsReported() async {
        let bench = Bench(demo: DemoController(activeSource: .persistedOverride, activeDocument: DemoController.customDocument))
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }

        XCTAssertEqual(session.configStatus?.activeSource, .known(.persistedOverride))
        guard case .summary(let summary)? = session.activeConfig else { return XCTFail("expected a summary") }
        XCTAssertEqual(summary.actions.map(\.title), ["Brake", "Shift light"])
        XCTAssertEqual(summary.profile, .custom)
    }

    func testNoActiveConfig() async {
        let bench = Bench(demo: DemoController(activeSource: .none))
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }
        XCTAssertEqual(session.activeConfig, ControllerSession.ActiveConfig.none)
    }

    func testNewerConfigSchemaIsShownAsUnreadable() async {
        let demo = DemoController()
        demo.deviceInfo.configSchemaVersion = 2
        let bench = Bench(demo: demo)
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }
        guard case .unreadable? = session.activeConfig else {
            return XCTFail("expected unreadable, got \(String(describing: session.activeConfig))")
        }
    }

    func testUnsupportedMajorInDeviceInfoIsIncompatible() async {
        // The radio's own pre-pairing check passes; device info says otherwise.
        let demo = DemoController()
        demo.deviceInfo.protocolMajor = 3
        let bench = Bench(demo: demo)
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .incompatible(major: 3) }
        XCTAssertNil(session.activeConfig)
    }

    func testDeviceInfoIsClearedOnDisconnectAndReadAgainOnReconnect() async {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }
        let cached = await session.client.deviceInfo
        XCTAssertEqual(cached?.firmwareVersion, "0.4.0-demo")

        // The controller restarts with new firmware while the link is down.
        bench.radio.powerOff(bench.peripheral.id)
        await bench.settle { session.phase == .offline }
        XCTAssertNil(session.deviceInfo)
        for _ in 0..<50 { await Task.yield() }
        let cleared = await session.client.deviceInfo
        XCTAssertNil(cleared, "the client must not keep device info across connections")

        bench.demo.deviceInfo.firmwareVersion = "0.5.0-demo"
        bench.radio.powerOn(bench.peripheral.id)
        await bench.settle { session.phase == .ready }
        XCTAssertEqual(session.deviceInfo?.firmwareVersion, "0.5.0-demo")
        let reread = await session.client.deviceInfo
        XCTAssertEqual(reread?.firmwareVersion, "0.5.0-demo")
    }

    func testClientOperationsFailUntilDeviceInfoIsReadAgain() async {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }

        bench.manager.disconnect()
        await bench.settle { session.phase == .offline }
        for _ in 0..<50 { await Task.yield() }
        do {
            _ = try await session.client.readConfigStatus()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? CompanionClientError, .deviceInfoNotRead)
        }
    }

    func testFailedReadCanBeRetried() async {
        let bench = Bench()
        var failStatus = true
        let demo = bench.demo
        bench.radio.readHandler = { _, characteristic in
            if characteristic == CompanionGATT.configStatus, failStatus {
                return .failure(.att(ATTErrorCode.busy.rawValue))
            }
            return demo.read(characteristic)
        }
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle {
            if case .failed = session.phase { return true }
            return false
        }

        failStatus = false
        session.reload()
        await bench.settle { session.phase == .ready }
    }

    func testDemoScenariosReachTheirLinkStates() async throws {
        let expectations: [DemoScenario: (LinkState) -> Bool] = [
            .notPaired: { $0 == .idle },
            .connecting: { if case .connecting = $0 { true } else { false } },
            .connected: { $0.isConnected },
            .customConfig: { $0.isConnected },
            .validationError: { $0.isConnected },
            .relinking: { $0 == .disconnected(.connectionLost("The connection has timed out unexpectedly."), willReconnect: true) },
            .incompatible: { $0 == .disconnected(.unsupportedProtocol(major: 2), willReconnect: false) },
            .bluetoothOff: { $0 == .poweredOff },
            .noAccess: { $0 == .unauthorized },
        ]
        for scenario in DemoScenario.allCases {
            let session = scenario.makeSession(latency: 0.001)
            let expected = try XCTUnwrap(expectations[scenario])
            var reached = false
            for _ in 0..<500 {
                if expected(session.connection.state) { reached = true; break }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(reached, "\(scenario) ended in \(session.connection.state)")
            if scenario == .connected {
                for _ in 0..<500 where session.phase != .ready {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                XCTAssertEqual(session.phase, .ready)
            }
        }
    }

    func testLiveTelemetryFollowsTheStream() async throws {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }

        let telemetry = LiveTelemetry(session: session)
        let run = Task { await telemetry.run() }
        var frame = DemoTelemetry()
        frame.engineRPM = 3200
        for sequence in 0..<200 where telemetry.frame.engineRPM.value != 3200 {
            frame.sequence = UInt8(sequence)
            bench.radio.sendNotification(from: bench.peripheral.id, characteristic: CompanionGATT.liveSignals, data: frame.encoded, immediately: true)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(telemetry.frame.engineRPM, SignalReading(availability: .freshnessUnverified, value: 3200))
        XCTAssertGreaterThan(telemetry.framesPerSecond, 0)

        run.cancel()
        await run.value
        XCTAssertEqual(telemetry.frame, .unknown)
        XCTAssertEqual(telemetry.framesPerSecond, 0)
    }

    func testLiveTelemetryWaitsForAReadySession() async {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        let telemetry = LiveTelemetry(session: session)
        await telemetry.run()
        XCTAssertEqual(telemetry.frame, .unknown)
        XCTAssertNil(telemetry.failure)
    }

    func testStallFrameDoesNotCountAsArrival() async {
        let bench = Bench()
        let telemetry = LiveTelemetry(session: ControllerSession(connection: bench.manager))
        let now = ContinuousClock.now
        telemetry.receive(.unknown, at: now)
        XCTAssertEqual(telemetry.framesPerSecond, 0)
    }

    func testProfileTrustsTheControllerSource() async throws {
        // Factory source, but not the app's copy of the factory profile.
        let factory = Bench(demo: DemoController(activeSource: .factory, activeDocument: DemoController.customDocument))
        let factorySession = ControllerSession(connection: factory.manager)
        await factory.connect()
        await factory.settle { factorySession.phase == .ready }
        guard case .summary(let factorySummary)? = factorySession.activeConfig else { return XCTFail("expected a summary") }
        XCTAssertEqual(factorySummary.profile, .factory)

        let track = Bench(demo: DemoController(activeSource: .persistedOverride, activeDocument: try PresetCatalog.resource("track.json")))
        let trackSession = ControllerSession(connection: track.manager)
        await track.connect()
        await track.settle { trackSession.phase == .ready }
        guard case .summary(let trackSummary)? = trackSession.activeConfig else { return XCTFail("expected a summary") }
        XCTAssertEqual(trackSummary.profile, .preset("Track"))
    }
}
