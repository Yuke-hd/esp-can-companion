import XCTest
import PresetSync
@testable import CANCompanion

final class PresetSyncSheetTests: XCTestCase {
    func testEveryPhaseExplainsItself() throws {
        let preset = try XCTUnwrap(PresetCatalog.bundled().first)
        let failure = SyncFailure(kind: .rejected, title: "Rejected", message: "Kept the current config.")
        let phases: [PresetSyncModel.Phase] = [
            .confirming(.preset(preset)), .confirming(.factory),
            .uploading(preset, fraction: 0.5), .validating(preset), .reverting,
            .restarting(.preset(preset)), .restarting(.factory),
            .succeeded(.preset(preset)), .succeeded(.factory),
            .failed(.preset(preset), failure), .failed(.factory, failure),
        ]
        for phase in phases {
            XCTAssertFalse(phase.title.isEmpty, "\(phase)")
            XCTAssertFalse(phase.message.isEmpty, "\(phase)")
            XCTAssertNotNil(phase.target, "\(phase)")
        }
        XCTAssertNil(PresetSyncModel.Phase.idle.target)
    }

    func testRejectionIsShownAsRejected() throws {
        let failure = SyncFailure(kind: .rejected, title: "", message: "")
        XCTAssertEqual(PresetSyncModel.Phase.failed(.factory, failure).pillTitle, "Rejected")
        XCTAssertEqual(PresetSyncModel.Phase.failed(.factory, failure).pillStatus, .alert)
        XCTAssertEqual(PresetSyncModel.Phase.succeeded(.factory).pillStatus, .live)
    }

    func testProgressPhasesTargetWhatIsBeingChanged() throws {
        let preset = try XCTUnwrap(PresetCatalog.bundled().first)
        XCTAssertEqual(PresetSyncModel.Phase.uploading(preset, fraction: 0).target, .preset(preset))
        XCTAssertEqual(PresetSyncModel.Phase.reverting.target, .factory)
    }
}
