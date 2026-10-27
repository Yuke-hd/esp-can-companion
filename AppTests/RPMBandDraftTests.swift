import XCTest
import CompanionLink
@testable import CANCompanion

@MainActor
final class RPMBandDraftTests: XCTestCase {
    func testDraftStartsFromTheBand() {
        let draft = RPMBandDraft(RPMBand(fill: .init(from: 1000, to: 6500), redline: 6000))
        XCTAssertEqual(draft.fillFrom, "1000")
        XCTAssertEqual(draft.fillTo, "6500")
        XCTAssertTrue(draft.redlineOn)
        XCTAssertEqual(draft.redline, "6000")
    }

    func testDraftWithRedlineOffKeepsARedlineToTurnBackOn() {
        let draft = RPMBandDraft(RPMBand(fill: .init(from: 0, to: 5000), redline: nil))
        XCTAssertFalse(draft.redlineOn)
        XCTAssertEqual(draft.redline, "5000", "the default redline, capped at the fill end")
        XCTAssertEqual(try draft.result.get(), RPMBand(fill: .init(from: 0, to: 5000), redline: nil))
    }

    func testValidDraftGivesItsBand() {
        var draft = RPMBandDraft(AppConfig.default.rpmBand)
        draft.redline = "4000"
        XCTAssertEqual(try draft.result.get(), RPMBand(fill: .init(from: 0, to: 6500), redline: 4000))
    }

    func testEmptyOrNonNumericFieldIsNamed() {
        var draft = RPMBandDraft(AppConfig.default.rpmBand)
        draft.fillTo = ""
        XCTAssertEqual(draft.problem, .notAWholeNumber(.fillTo))
        draft.fillTo = "65.5"
        XCTAssertEqual(draft.problem, .notAWholeNumber(.fillTo))
        draft.fillTo = "6500"
        draft.redline = "abc"
        XCTAssertEqual(draft.problem, .notAWholeNumber(.redline))
        draft.redlineOn = false
        XCTAssertNil(draft.problem, "a hidden redline field is ignored")
    }

    func testRuleBreaksAreReportedWithTheirOwnMessage() {
        var draft = RPMBandDraft(AppConfig.default.rpmBand)
        draft.redline = "7000"
        XCTAssertEqual(draft.problem, .rule(.redlineAboveFillEnd))
        XCTAssertEqual(draft.problem?.message, "Redline must be at or below fill end.")
        draft.redline = "6000"
        draft.fillTo = "13000"
        XCTAssertEqual(draft.problem?.message, "Fill end must be 12000 rpm or less.")
        draft.fillTo = "0"
        XCTAssertEqual(draft.problem?.message, "Fill start must be below fill end.")
    }

    func testSettingsSummaryShowsTheRedline() {
        XCTAssertEqual(AppConfig.default.rpmBand.settingsSummary, "Redline 6000")
        XCTAssertEqual(RPMBand(fill: .init(from: 0, to: 6500), redline: nil).settingsSummary, "Redline off")
    }

    // MARK: - Commit rule

    private func makeModel() -> (AppModel, InMemoryAppConfigStore) {
        let store = InMemoryAppConfigStore()
        return (AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: store), store)
    }

    func testKeystrokesDoNotChangeTheModelUntilCommit() {
        let (app, store) = makeModel()
        var draft = RPMBandDraft(app.appConfig.rpmBand)
        for prefix in ["", "7", "70", "700"] { draft.redline = prefix }
        XCTAssertEqual(app.appConfig.rpmBand, AppConfig.default.rpmBand)
        XCTAssertEqual(store.appConfig.rpmBand, AppConfig.default.rpmBand)
    }

    func testCommittingAnInvalidEditKeepsTheBandAndReportsTheProblem() {
        let (app, store) = makeModel()
        var draft = RPMBandDraft(app.appConfig.rpmBand)
        for prefix in ["", "7", "70", "700", "7000"] { draft.redline = prefix }
        XCTAssertEqual(app.commitRPMBand(&draft), .rule(.redlineAboveFillEnd))
        XCTAssertEqual(app.appConfig.rpmBand.redline, 6000)
        XCTAssertEqual(store.appConfig.rpmBand.redline, 6000)
        XCTAssertEqual(draft.redline, "7000", "the invalid entry stays on screen to fix")
    }

    func testCommittingAValidEditAppliesAndSavesIt() {
        let (app, store) = makeModel()
        var draft = RPMBandDraft(app.appConfig.rpmBand)
        draft.redline = "4000"
        XCTAssertNil(app.commitRPMBand(&draft))
        let band = RPMBand(fill: .init(from: 0, to: 6500), redline: 4000)
        XCTAssertEqual(app.appConfig.rpmBand, band)
        XCTAssertEqual(store.appConfig.rpmBand, band)
    }

    func testRedlineOffThenOnRestoresThePreviousRedline() {
        let (app, _) = makeModel()
        var draft = RPMBandDraft(app.appConfig.rpmBand)
        draft.redlineOn = false
        XCTAssertNil(app.commitRPMBand(&draft))
        XCTAssertNil(app.appConfig.rpmBand.redline)
        draft.redlineOn = true
        XCTAssertNil(app.commitRPMBand(&draft))
        XCTAssertEqual(app.appConfig.rpmBand.redline, 6000)
    }

    func testCommitTrimsAndShowsTheCanonicalNumber() {
        let (app, _) = makeModel()
        var draft = RPMBandDraft(app.appConfig.rpmBand)
        draft.fillFrom = " 0500 "
        draft.redline = "+06000"
        XCTAssertNil(app.commitRPMBand(&draft))
        XCTAssertEqual(app.appConfig.rpmBand, RPMBand(fill: .init(from: 500, to: 6500), redline: 6000))
        XCTAssertEqual(draft.fillFrom, "500")
        XCTAssertEqual(draft.redline, "6000")
    }

    func testHugeWholeNumberGetsTheRangeMessage() {
        var draft = RPMBandDraft(AppConfig.default.rpmBand)
        draft.fillTo = "99999999999999999999"
        XCTAssertEqual(draft.problem, .rule(.fillEndAboveMaximum))
        draft.fillTo = "1e5"
        XCTAssertEqual(draft.problem, .notAWholeNumber(.fillTo))
    }
}
