import XCTest
import CompanionProtocol
@testable import CANCompanion

final class RuleEditingTests: XCTestCase {
    func testRPMRuleDisplaysWholeNumbersAndPreservesFineTuning() throws {
        var draft = RuleDraft(.sampledState(condition, releaseThreshold: 5800))
        XCTAssertEqual(draft.number, "6000")
        XCTAssertEqual(draft.release, "5800")
        draft.number = "6001"
        draft.release = "5799"
        let saved = RuleDraft(try draft.makeRule())
        XCTAssertEqual(saved.number, "6001")
        XCTAssertEqual(saved.release, "5799")
        draft.number = "6001.5"
        XCTAssertThrowsError(try draft.makeRule()) { error in
            XCTAssertEqual(error as? RuleDraft.InputError, .wholeRPM("Operand"))
        }
    }

    func testRPMRangeUsesWholeInputButAllowsFractionalOutputMapping() throws {
        var draft = RuleDraft(.range(.init(action: "shift", signalKey: "vehicle.engine_rpm",
                                          input: .init(from: 1001, to: 6499), output: .init(from: 0.25, to: 1))))
        XCTAssertEqual(draft.inputFrom, "1001")
        XCTAssertEqual(draft.inputTo, "6499")
        XCTAssertEqual(try RuleDraft(try draft.makeRule()).makeRule(), try draft.makeRule())
        draft.inputFrom = "1001.5"
        XCTAssertThrowsError(try draft.makeRule()) { error in
            XCTAssertEqual(error as? RuleDraft.InputError, .wholeRPM("Input from"))
        }
    }

    private let condition = ControllerConfig.Condition(
        action: "shift", signalKey: "vehicle.engine_rpm", comparison: .greater,
        operand: .number(6000), freshness: .freshOrUnverified
    )

    func testRoundTripPreservesEveryRuleKindAndProperty() throws {
        let rules: [ControllerConfig.Rule] = [
            .state(condition),
            .sampledState(condition, releaseThreshold: 5800),
            .sampledState(condition),
            .event(condition, edge: .becomesFalse),
            .range(.init(action: "shift", signalKey: "custom.numeric",
                         input: .init(from: -1.5, to: 6500), output: .init(from: 0.25, to: 1), freshness: .fresh)),
            .state(.init(action: "shift", signalKey: "vehicle.turn_state", comparison: .notEqual, operand: .choice("left"))),
            .event(.init(action: "shift", signalKey: "vehicle.brake_pressed", comparison: .equal,
                         operand: .boolean(false), freshness: .freshOrUnverified), edge: .becomesTrue),
        ]
        for rule in rules {
            XCTAssertEqual(try RuleDraft(rule).makeRule(), rule)
        }
    }

    func testEditingAConditionDoesNotMutateTheOriginalUntilSaved() throws {
        let original = ControllerConfig.Rule.sampledState(condition, releaseThreshold: 5800)
        var draft = RuleDraft(original)
        draft.action = "brake"
        draft.signalKey = "custom.sensor"
        draft.comparison = .lessOrEqual
        draft.number = "-2.5"
        draft.release = "-3"
        draft.freshness = .fresh

        XCTAssertEqual(original, .sampledState(condition, releaseThreshold: 5800))
        XCTAssertEqual(try draft.makeRule(), .sampledState(.init(
            action: "brake", signalKey: "custom.sensor", comparison: .lessOrEqual,
            operand: .number(-2.5), freshness: .fresh), releaseThreshold: -3))
    }

    func testBrakeFreshnessIsNormalizedForEveryRuleKind() throws {
        for kind in RuleDraft.Kind.allCases {
            var draft = RuleDraft(.state(condition))
            draft.kind = kind
            draft.signalKey = "vehicle.brake_pressed"
            draft.freshness = .fresh
            let saved = RuleDraft(try draft.makeRule())

            XCTAssertEqual(saved.freshness, .freshOrUnverified)
            XCTAssertEqual(draft.availableFreshness, [.freshOrUnverified])
        }
    }

    func testOptionalReleaseCanBeRemovedAndEventEdgeCanChange() throws {
        var draft = RuleDraft(.sampledState(condition, releaseThreshold: 5800))
        draft.hasRelease = false
        XCTAssertEqual(try draft.makeRule(), .sampledState(condition))

        draft.kind = .event
        draft.edge = .becomesFalse
        XCTAssertEqual(try draft.makeRule(), .event(condition, edge: .becomesFalse))
    }

    func testChoiceAndBooleanOperandEditsArePersisted() throws {
        var draft = RuleDraft(.state(condition))
        draft.operandKind = .choice
        draft.choice = "hazard"
        XCTAssertEqual(RuleDraft(try draft.makeRule()).choice, "hazard")
        draft.operandKind = .boolean
        draft.boolean = false
        XCTAssertEqual(RuleDraft(try draft.makeRule()).boolean, false)
    }

    func testRangeValuesPersistWithoutClientSemanticValidation() throws {
        var draft = RuleDraft(.state(condition))
        draft.kind = .range
        draft.inputFrom = "7000"
        draft.inputTo = "1000"
        draft.outputFrom = "-0.5"
        draft.outputTo = "2"

        XCTAssertEqual(try draft.makeRule(), .range(.init(
            action: "shift", signalKey: "vehicle.engine_rpm", input: .init(from: 7000, to: 1000),
            output: .init(from: -0.5, to: 2), freshness: .freshOrUnverified)))
    }

    func testUnrepresentableNumericInputReportsTheFieldInsteadOfSilentlyKeepingOldValue() {
        for invalid in ["", "not a number", "nan", "inf"] {
            var draft = RuleDraft(.state(condition))
            draft.number = invalid
            XCTAssertThrowsError(try draft.makeRule()) { error in
                XCTAssertEqual(error as? RuleDraft.InputError, .number("Operand"))
            }
        }
    }
}
