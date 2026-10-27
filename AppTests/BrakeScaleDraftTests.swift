import XCTest
import CompanionLink
@testable import CANCompanion

@MainActor
final class BrakeScaleDraftTests: XCTestCase {
    private func model(scale: Double = 70) -> (AppModel, InMemoryAppConfigStore) {
        var config = AppConfig.default
        config.brakePressureBarScale = scale
        let store = InMemoryAppConfigStore(appConfig: config)
        return (AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: store), store)
    }

    func testDraftStartsFromTheScale() {
        XCTAssertEqual(BrakeScaleDraft(70).text, "70")
        XCTAssertEqual(try BrakeScaleDraft(120).result.get(), 120)
    }

    func testRangeIsTenToTwoHundredBar() {
        var draft = BrakeScaleDraft(70)
        for (text, problem) in [("9", BrakeScaleDraft.Problem.outOfRange), ("201", .outOfRange), ("0", .outOfRange),
                                ("-50", .outOfRange), ("", .notAWholeNumber), ("70.5", .notAWholeNumber),
                                ("abc", .notAWholeNumber)] {
            draft.text = text
            XCTAssertEqual(draft.problem, problem, "for \(text)")
        }
        for text in ["10", "200", " 150 "] {
            draft.text = text
            XCTAssertNil(draft.problem, "for \(text)")
        }
    }

    func testValidCommitAppliesSavesAndCanonicalizes() {
        let (app, store) = model()
        var draft = BrakeScaleDraft(70)
        draft.text = "0120"
        XCTAssertNil(app.commitBrakeScale(&draft))
        XCTAssertEqual(app.appConfig.brakePressureBarScale, 120)
        XCTAssertEqual(store.appConfig.brakePressureBarScale, 120)
        XCTAssertEqual(draft.text, "120")
    }

    func testInvalidCommitKeepsTheLastGoodScaleAndTheTypedText() {
        let (app, store) = model(scale: 90)
        var draft = BrakeScaleDraft(90)
        draft.text = "500"
        XCTAssertEqual(app.commitBrakeScale(&draft), .outOfRange)
        XCTAssertEqual(app.appConfig.brakePressureBarScale, 90)
        XCTAssertEqual(store.appConfig.brakePressureBarScale, 90)
        XCTAssertEqual(draft.text, "500")
    }

    func testSetScaleRejectsOutOfRangeValues() {
        let (app, _) = model()
        XCTAssertFalse(app.setBrakePressureBarScale(.nan))
        XCTAssertFalse(app.setBrakePressureBarScale(5))
        XCTAssertEqual(app.appConfig.brakePressureBarScale, 70)
        XCTAssertTrue(app.setBrakePressureBarScale(10))
        XCTAssertEqual(app.appConfig.brakePressureBarScale, 10)
    }

    func testProblemMessagesNameTheRange() {
        XCTAssertEqual(BrakeScaleDraft.Problem.outOfRange.message, "Brake pressure scale must be 10 to 200 bar.")
        XCTAssertTrue(BrakeScaleDraft.Problem.notAWholeNumber.message.contains("whole number of bar"))
    }
}
