import XCTest
import CompanionFakes
import CompanionProtocol
import PresetSync
@testable import CANCompanion

@MainActor
final class SetupDraftSyncTests: XCTestCase {
    func testEditedRangeAndReleaseAreUploadedAndConfirmedByCRC() async throws {
        let presets = try PresetCatalog.bundled()
        let selection = SetupSelection()
        selection.select(try XCTUnwrap(presets.first))
        selection.setRPMInputRange(.init(lower: 1000, upper: 6500))
        selection.setRedZoneThresholds(.init(triggerAbove: 6000, releaseBelow: 5800))
        let draft = try XCTUnwrap(selection.preset)
        let controller = FakeController()
        controller.factoryDocument = try PresetCatalog.resource("factory.json")
        controller.activeDocument = controller.factoryDocument
        let sync = PresetSyncModel(presets: presets, link: FakePresetSyncLink(controller: controller))
        sync.requestPush(draft)
        await sync.confirm()
        XCTAssertEqual(sync.phase, .succeeded(.preset(draft)))
        XCTAssertEqual(try ControllerConfig(canonicalJSON: controller.activeDocument), draft.config)
        XCTAssertEqual(selection.status(active: sync.active), .onCar)
        XCTAssertNil(sync.active?.presetID, "A modified config must not claim the bundled preset is running")
        selection.setRPMInputRange(.init(lower: 1200, upper: 6500))
        XCTAssertEqual(selection.status(active: sync.active), .pending)
    }

    func testControllerRejectionKeepsTheDraftPendingAndExistingConfigIntact() async throws {
        let presets = try PresetCatalog.bundled()
        let selection = SetupSelection()
        selection.select(try XCTUnwrap(presets.first))
        selection.setRPMInputRange(.init(lower: 1000, upper: 6500))
        let draft = try XCTUnwrap(selection.preset)
        let controller = FakeController()
        controller.factoryDocument = try PresetCatalog.resource("factory.json")
        controller.activeDocument = controller.factoryDocument
        controller.commitOutcome = .reject(category: 3, code: 10, validation: 18, index: 4, path: "outputs[4].zone.length")
        let sync = PresetSyncModel(presets: presets, link: FakePresetSyncLink(controller: controller))
        await sync.refresh()
        sync.requestPush(draft)
        await sync.confirm()
        guard case .failed(_, let failure) = sync.phase else { return XCTFail("Expected controller rejection") }
        XCTAssertEqual(failure.field, "outputs[4].zone.length")
        XCTAssertEqual(selection.status(active: sync.active), .pending)
        XCTAssertEqual(selection.preset, draft)
        XCTAssertEqual(controller.activeDocument, controller.factoryDocument)
    }
}
