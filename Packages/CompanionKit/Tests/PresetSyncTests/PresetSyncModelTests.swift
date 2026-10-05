import XCTest
import CompanionProtocol
import CompanionFakes
@testable import PresetSync

/// Drives the sync flow against the in-memory controller. Every test is
/// `async` because Linux XCTest skips sync tests in a `@MainActor` case.
@MainActor
final class PresetSyncModelTests: XCTestCase {
    private var controller: FakeController!
    private var link: FakePresetSyncLink!
    private var model: PresetSyncModel!
    private var presets: [Preset] = []
    private var factoryDocument = Data()
    private var changes = 0

    override func setUp() async throws {
        presets = try PresetCatalog.bundled()
        factoryDocument = try PresetCatalog.resource("factory.json")
        controller = FakeController()
        controller.factoryDocument = factoryDocument
        controller.activeDocument = factoryDocument
        link = FakePresetSyncLink(controller: controller)
        model = PresetSyncModel(presets: presets, link: link)
        changes = 0
        model.onChange = { [unowned self] in self.changes += 1 }
    }

    private var earlyShift: Preset { presets[0] }

    private func push(_ preset: Preset) async {
        model.requestPush(preset)
        XCTAssertEqual(model.phase, .confirming(.preset(preset)))
        await model.confirm()
    }

    private func failure() -> SyncFailure? {
        if case .failed(_, let failure) = model.phase { return failure }
        return nil
    }

    // MARK: Push

    func testPushSucceedsOnlyAfterTheControllerRunsThePreset() async throws {
        await push(earlyShift)

        XCTAssertEqual(model.phase, .succeeded(.preset(earlyShift)))
        XCTAssertEqual(link.restarts, 1)
        XCTAssertEqual(controller.activeSource, 1)
        XCTAssertEqual(controller.activeDocument, try earlyShift.config.encodedJSON())
        XCTAssertEqual(model.active?.presetID, earlyShift.id)
        XCTAssertEqual(model.active?.isFactory, false)
        XCTAssertEqual(changes, 1)
    }

    func testForcedValidationErrorShowsTheControllersCodeAndField() async throws {
        controller.commitOutcome = .reject(category: 3, code: 10, validation: 18, index: 4, path: "outputs[4].zone.length")
        await model.refresh()
        let before = model.active

        await push(earlyShift)

        XCTAssertEqual(model.phase, .failed(.preset(earlyShift), SyncFailure(
            kind: .rejected,
            title: "The controller rejected this preset",
            message: "Its validation found a problem, so it kept the current config.",
            code: "semantic · schemaValidation · zoneOutOfRange",
            field: "outputs[4].zone.length"
        )))
        XCTAssertEqual(link.restarts, 0, "A rejected commit does not restart the controller")
        XCTAssertEqual(controller.activeDocument, factoryDocument)
        XCTAssertEqual(model.active, before)
        XCTAssertEqual(changes, 0)
    }

    func testApplyRejectionNamesTheSectionEntry() async throws {
        controller.commitOutcome = .applyReject(stage: 4, section: 3, index: 4, engine: 0)
        await push(earlyShift)

        let failure = try XCTUnwrap(failure())
        XCTAssertEqual(failure.kind, .rejected)
        XCTAssertEqual(failure.code, "stage sinkRegistration")
        XCTAssertEqual(failure.field, "outputs[4]")
        XCTAssertEqual(link.restarts, 0)
    }

    func testStorageFailureSaysTheNextBootIsUncertain() async throws {
        controller.commitOutcome = .storageFailure
        await push(earlyShift)

        XCTAssertEqual(failure()?.kind, .storage)
        XCTAssertEqual(link.restarts, 0)
    }

    func testLinkDropDuringCommitIsNeverReportedAsSuccess() async throws {
        controller.commitOutcome = .dropLink
        await push(earlyShift)

        XCTAssertEqual(failure()?.kind, .outcomeUnknown)
        XCTAssertEqual(link.restarts, 1, "Reconnects to show what runs now")
        XCTAssertEqual(model.active?.presetID, earlyShift.id)
        XCTAssertEqual(changes, 0)
    }

    func testOtherLinkFailureDuringCommitIsAnUnknownOutcome() async throws {
        controller.beforeWrite = { _, _, value in
            if value == ConfigWritePDU.commit.encoded { throw CompanionTransportError.other("link failed") }
        }
        await push(earlyShift)

        XCTAssertEqual(failure()?.kind, .outcomeUnknown)
        XCTAssertEqual(changes, 0)
    }

    func testRevertWithOtherLinkFailureChecksTheController() async throws {
        await push(earlyShift)
        controller.beforeWrite = { _, characteristic, _ in
            if characteristic == .command { throw CompanionTransportError.other(nil) }
        }

        model.requestRevert()
        await model.confirm()

        XCTAssertEqual(link.restarts, 2, "An unknown revert outcome is checked after reconnecting")
        XCTAssertEqual(failure()?.kind, .notActive, "The command never ran, so the preset is still active")
    }

    func testOverrideRejectedAtBootIsNotActive() async throws {
        controller.overrideFailsAtBoot = (code: 9, validation: 18)
        await push(earlyShift)

        let failure = try XCTUnwrap(failure())
        XCTAssertEqual(failure.kind, .notActive)
        XCTAssertEqual(failure.code, "invalidValue · zoneOutOfRange")
        XCTAssertEqual(model.active?.isFactory, true)
        XCTAssertNotNil(model.active?.bootDiagnostic)
        XCTAssertEqual(changes, 0)
    }

    func testPushWithoutAConnectionFails() async throws {
        controller.isConnected = false
        await push(earlyShift)

        XCTAssertEqual(failure()?.kind, .failed)
        XCTAssertEqual(failure()?.message, "No controller is connected.")
        XCTAssertTrue(controller.configWrites.isEmpty)
    }

    func testUploadReachesTheControllerInChunks() async throws {
        controller.maximumWrite = 61
        await push(presets[1])

        XCTAssertEqual(model.phase, .succeeded(.preset(presets[1])))
        let chunks = controller.configWrites.filter { $0.first == 0x02 }
        XCTAssertGreaterThan(chunks.count, 1)
    }

    // MARK: Revert

    func testRevertToFactoryIsConfirmedAfterRestart() async throws {
        await push(earlyShift)
        XCTAssertEqual(controller.activeSource, 1)

        model.requestRevert()
        XCTAssertEqual(model.phase, .confirming(.factory))
        await model.confirm()

        XCTAssertEqual(model.phase, .succeeded(.factory))
        XCTAssertEqual(controller.commandWrites, [CompanionCommand.revertToFactory.encoded])
        XCTAssertEqual(controller.activeDocument, factoryDocument)
        XCTAssertEqual(model.active?.isFactory, true)
        XCTAssertNil(model.active?.presetID)
        XCTAssertEqual(changes, 2)
    }

    func testRevertWithUnknownOutcomeChecksTheController() async throws {
        await push(earlyShift)
        controller.commandsDropLink = true

        model.requestRevert()
        await model.confirm()

        XCTAssertEqual(model.phase, .succeeded(.factory))
        XCTAssertEqual(link.restarts, 2)
    }

    func testRevertIsNotConfirmedWhenLightingFailsToStart() async throws {
        await push(earlyShift)
        controller.lightingFailsAtBoot = true

        model.requestRevert()
        await model.confirm()

        XCTAssertEqual(model.phase, .failed(.factory, .factoryLightingFailed))
        XCTAssertEqual(model.active?.isFactory, true)
        XCTAssertEqual(model.active?.lightingSetupFailed, true)
        XCTAssertEqual(changes, 1, "Only the push was confirmed")
    }

    func testPushIsNotConfirmedOnTheConnectionBeforeTheRestart() async throws {
        await push(earlyShift)
        link.skipsRestart = true

        await push(earlyShift)

        XCTAssertEqual(failure()?.kind, .outcomeUnknown)
        XCTAssertEqual(changes, 1)
    }

    func testRevertIsNotConfirmedOnTheConnectionBeforeTheRestart() async throws {
        link.skipsRestart = true

        model.requestRevert()
        await model.confirm()

        XCTAssertEqual(failure()?.kind, .outcomeUnknown)
        XCTAssertEqual(changes, 0)
    }

    func testSecondStorageFailureSaysStorageIsFailing() async throws {
        controller.commitOutcome = .storageFailure
        await push(earlyShift)
        XCTAssertEqual(failure()?.title, "The controller could not save the preset")

        controller.revertFails = true
        model.requestRevert()
        await model.confirm()
        XCTAssertEqual(failure(), .storageFailing)

        controller.commitOutcome = .save
        controller.revertFails = false
        await push(earlyShift)
        XCTAssertEqual(model.phase, .succeeded(.preset(earlyShift)))
        controller.commitOutcome = .storageFailure
        await push(earlyShift)
        XCTAssertEqual(failure()?.title, "The controller could not save the preset", "A success resets the count")
    }

    func testRevertStorageFailureLeavesTheConfig() async throws {
        await push(earlyShift)
        controller.revertFails = true

        model.requestRevert()
        await model.confirm()

        XCTAssertEqual(failure()?.kind, .storage)
        XCTAssertEqual(link.restarts, 1, "Only the push restarted the controller")
        XCTAssertEqual(controller.activeSource, 1)
    }

    // MARK: State machine

    func testConfirmDoesNothingWithoutARequest() async throws {
        await model.confirm()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(controller.writes.isEmpty)
    }

    func testDismissReturnsToIdle() async throws {
        model.requestPush(earlyShift)
        model.dismiss()
        XCTAssertEqual(model.phase, .idle)

        controller.commitOutcome = .storageFailure
        await push(earlyShift)
        model.dismiss()
        XCTAssertEqual(model.phase, .idle)
    }

    func testRequestsAreIgnoredWhileBusy() async throws {
        controller.writeDelay = .milliseconds(20)
        model.requestPush(earlyShift)
        let run = Task { await model.confirm() }
        while !model.phase.isBusy { await Task.yield() }

        model.requestRevert()
        model.dismiss()
        XCTAssertTrue(model.phase.isBusy)

        await run.value
        XCTAssertEqual(model.phase, .succeeded(.preset(earlyShift)))
    }

    func testRefreshWaitsOutABusySync() async throws {
        controller.writeDelay = .milliseconds(20)
        model.requestPush(earlyShift)
        let run = Task { await model.confirm() }
        while !model.phase.isBusy { await Task.yield() }

        let readsBefore = controller.withLock { controller.reads }
        await model.refresh()
        XCTAssertEqual(controller.withLock { controller.reads }, readsBefore, "No reads while busy")

        await run.value
        XCTAssertEqual(model.phase, .succeeded(.preset(earlyShift)))
    }

    func testRefreshIdentifiesTheActivePreset() async throws {
        await model.refresh()
        XCTAssertEqual(model.active?.isFactory, true)
        XCTAssertNil(model.active?.presetID)

        controller.activeSource = 1
        controller.activeDocument = try presets[2].config.encodedJSON()
        await model.refresh()
        XCTAssertEqual(model.active?.presetID, presets[2].id)
        XCTAssertNil(model.refreshError)

        controller.isConnected = false
        await model.refresh()
        XCTAssertNil(model.active)
        XCTAssertEqual(model.refreshError, "No controller is connected.")
    }
}
