import XCTest
import BLETransport
import CompanionProtocol
import PresetSync
@testable import CompanionLink

@MainActor
final class DemoSyncTests: XCTestCase {
    func testPushRunsThePresetAfterRadioReconnectAndRefreshesHome() async throws {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }
        let presets = try PresetCatalog.bundled()
        let preset = presets[0]
        let model = PresetSyncModel(presets: presets, link: session)
        var statuses: [ConfigStatus] = []
        let observation = bench.manager.observeNotifications { uuid, bytes in
            if uuid == CompanionGATT.configStatus, let status = try? ConfigStatus(decoding: bytes) {
                statuses.append(status)
            }
        }
        defer { observation.cancel() }
        var changes = 0
        model.onChange = { changes += 1 }
        model.requestPush(preset)

        try await run(bench) { await model.confirm() }

        XCTAssertEqual(model.phase, .succeeded(.preset(preset)))
        XCTAssertEqual(model.active?.presetID, preset.id)
        XCTAssertEqual(bench.demo.activeDocument, try preset.config.encodedJSON())
        XCTAssertEqual(session.configStatus?.activeSource, .known(.persistedOverride))
        XCTAssertEqual(session.activeConfig, .summary(ConfigSummary(preset.config, profile: .preset(preset.name))))
        XCTAssertEqual(changes, 1)
        XCTAssertGreaterThan(bench.radio.receivedWrites.filter { $0.data.first == 0x02 }.count, 1)
        XCTAssertGreaterThan(statuses.filter { $0.receivedLength > 0 }.count, 1)
        XCTAssertEqual(statuses.last?.result, .known(.saved))
        XCTAssertEqual(statuses.last?.savedCRC32, CRC32.checksum(try preset.config.encodedJSON()))
    }

    func testRevertRestartsTheRadioAndRefreshesHomeToFactory() async throws {
        let bench = Bench(demo: DemoController(activeSource: .persistedOverride, activeDocument: DemoController.customDocument))
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }
        let model = PresetSyncModel(presets: try PresetCatalog.bundled(), link: session)
        model.requestRevert()

        try await run(bench) { await model.confirm() }

        XCTAssertEqual(model.phase, .succeeded(.factory))
        XCTAssertEqual(model.active?.isFactory, true)
        XCTAssertEqual(bench.demo.activeDocument, DemoController.factoryDocument)
        XCTAssertEqual(session.configStatus?.activeSource, .known(.factory))
        XCTAssertEqual(session.activeConfig, .summary(ConfigSummary(try PresetCatalog.factory(), profile: .factory)))
    }

    func testRejectedPresetReportsControllerFieldAndCodeWithoutRestart() async throws {
        let demo = DemoController()
        demo.rejectsConfig = true
        let bench = Bench(demo: demo)
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }
        let presets = try PresetCatalog.bundled()
        let model = PresetSyncModel(presets: presets, link: session)
        try await run(bench) { await model.refresh() }
        let before = model.active
        var changes = 0
        model.onChange = { changes += 1 }
        model.requestPush(presets[0])

        try await run(bench) { await model.confirm() }

        guard case .failed(_, let failure) = model.phase else { return XCTFail("Expected rejection") }
        XCTAssertEqual(failure.kind, .rejected)
        XCTAssertEqual(failure.code, "semantic · schemaValidation · zoneOutOfRange")
        XCTAssertEqual(failure.field, "outputs[4].zone.length")
        XCTAssertEqual(model.active, before)
        XCTAssertEqual(demo.activeDocument, DemoController.factoryDocument)
        XCTAssertEqual(demo.state, .idle)
        XCTAssertTrue(bench.radio.connectedPeripherals.contains(bench.peripheral.id))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(changes, 0)
    }

    func testReadPageSelectionDoesNotCauseAPendingControllerToRestart() async throws {
        let scheduler = ManualScheduler()
        let peripheral = BLETransport.FakeController()
        let radio = FakeRadio(controllers: [peripheral], scheduler: scheduler, latency: 0)
        let demo = DemoController()
        demo.attach(to: radio, scheduler: scheduler)
        radio.connect(peripheral.id)
        scheduler.runUntilIdle()
        demo.state = .restartPending

        let error = radio.writeHandler?(CompanionGATT.config, Data([0x05, 0, 0]))
        scheduler.advance(by: 1)

        XCTAssertNil(error)
        XCTAssertEqual(demo.state, .restartPending, "Only a successful commit or revert schedules restart")
        XCTAssertTrue(radio.connectedPeripherals.contains(peripheral.id))
    }

    func testValidationErrorLaunchScenarioRejectsWithControllerDiagnostics() async throws {
        let session = DemoScenario.validationError.makeSession(latency: 0.001)
        for _ in 0..<500 where session.phase != .ready {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(session.phase, .ready)
        let presets = try PresetCatalog.bundled()
        let model = PresetSyncModel(presets: presets, link: session)
        model.requestPush(presets[0])

        await model.confirm()

        guard case .failed(_, let failure) = model.phase else { return XCTFail("Expected validation rejection") }
        XCTAssertEqual(failure.field, "outputs[4].zone.length")
        XCTAssertEqual(session.configStatus?.activeSource, .known(.factory))
        XCTAssertEqual(session.phase, .ready)
    }

    func testRepeatedRevertBeforeRestartSchedulesOnlyOneRestart() async throws {
        let scheduler = ManualScheduler()
        let peripheral = BLETransport.FakeController()
        let radio = FakeRadio(controllers: [peripheral], scheduler: scheduler, latency: 0)
        let demo = DemoController()
        demo.attach(to: radio, scheduler: scheduler)
        radio.connect(peripheral.id)
        scheduler.runUntilIdle()
        XCTAssertNil(radio.writeHandler?(CompanionGATT.command, CompanionCommand.revertToFactory.encoded))
        scheduler.advance(by: 0.1)
        XCTAssertNil(radio.writeHandler?(CompanionGATT.command, CompanionCommand.revertToFactory.encoded))
        scheduler.advance(by: 0.55)
        demo.state = .receiving

        scheduler.advance(by: 0.1)

        XCTAssertEqual(demo.state, .receiving, "The duplicate command must not restart the controller again")
    }

    private func run(_ bench: Bench, _ operation: @escaping @MainActor () async -> Void) async throws {
        var finished = false
        let task = Task { await operation(); finished = true }
        for _ in 0..<3_000 where !finished {
            bench.scheduler.advance(by: 0.01)
            try await Task.sleep(for: .milliseconds(1))
        }
        if !finished {
            task.cancel()
            XCTFail("Demo sync did not finish after the simulated restart")
            return
        }
        await task.value
    }
}
