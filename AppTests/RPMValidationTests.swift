import XCTest
import PresetSync
import CompanionProtocol
@testable import CANCompanion

final class RPMValidationTests: XCTestCase {
    private func config(minimum: Double = 1000, maximum: Double = 6500,
                        redLine: Double = 6000, release: Double? = 5800) -> ControllerConfig {
        var config = ControllerConfig()
        config.rules = [
            .range(.init(action: "rpm_fill", signalKey: "vehicle.engine_rpm",
                         input: .init(from: minimum, to: maximum), output: .init(from: 0, to: 1))),
            .sampledState(.init(action: "red_zone", signalKey: "vehicle.engine_rpm",
                                comparison: .greater, operand: .number(redLine)), releaseThreshold: release)
        ]
        return config
    }

    func testBundledPresetsAndValidFineRPMValuesPass() throws {
        for preset in try PresetCatalog.bundled() {
            XCTAssertTrue(RPMValidation.issues(in: preset.config).isEmpty, preset.name)
        }
        XCTAssertTrue(RPMValidation.issues(in: config(minimum: 0, maximum: 12000, redLine: 11999, release: 11998)).isEmpty)
        XCTAssertTrue(RPMValidation.issues(in: config(minimum: 1001, maximum: 6499, redLine: 6001, release: nil)).isEmpty)
    }

    func testEqualOrReversedRangeIsRejected() {
        for minimum in [6500.0, 6501] {
            XCTAssertTrue(RPMValidation.issues(in: config(minimum: minimum)).contains {
                $0.ruleIndex == 0 && $0.field == .inputTo && $0.problem == .rangeOrder
            })
        }
    }

    func testRPMBoundsAndWholeNumbersApplyToEveryRPMField() {
        for invalid in [-1.0, 12001, .infinity, .nan, 1001.5] {
            let cases: [(ControllerConfig, Int, RPMValidation.Issue.Field)] = [
                (config(minimum: invalid), 0, .inputFrom), (config(maximum: invalid), 0, .inputTo),
                (config(redLine: invalid), 1, .trigger), (config(release: invalid), 1, .release)
            ]
            for (config, index, field) in cases {
                XCTAssertTrue(RPMValidation.issues(in: config).contains { $0.ruleIndex == index && $0.field == field })
            }
        }
    }

    func testRedLineMustBeStrictlyBelowMaximumRPM() {
        for redLine in [6500.0, 6501] {
            XCTAssertTrue(RPMValidation.issues(in: config(redLine: redLine)).contains {
                $0.ruleIndex == 1 && $0.field == .trigger && $0.problem == .redLineOrder
            })
        }
    }

    func testReleaseMustBeStrictlyBelowTriggerRPM() {
        for release in [6000.0, 6001] {
            XCTAssertTrue(RPMValidation.issues(in: config(release: release)).contains {
                $0.ruleIndex == 1 && $0.field == .release && $0.problem == .releaseOrder
            })
        }
    }

    func testAdvancedComparisonChangesCannotBypassRedLineReleaseValidation() {
        for comparison in ControllerConfig.Comparison.allCases {
            var config = config()
            config.rules[1] = .sampledState(.init(action: "red_zone", signalKey: "vehicle.engine_rpm",
                                                comparison: comparison, operand: .number(6000)), releaseThreshold: 6000)
            XCTAssertTrue(RPMValidation.issues(in: config).contains { $0.problem == .releaseOrder }, comparison.rawValue)
        }
    }

    func testCustomSignalsAndFractionalOutputMappingAreNotRestricted() {
        var config = config()
        config.rules[0] = .range(.init(action: "rpm_fill", signalKey: "vehicle.engine_rpm",
                                       input: .init(from: 0, to: 6500), output: .init(from: 0.25, to: 1)))
        config.rules.append(.range(.init(action: "custom", signalKey: "custom.sensor",
                                         input: .init(from: 1.5, to: -2.5), output: .init(from: 2, to: -1))))
        XCTAssertTrue(RPMValidation.issues(in: config).isEmpty)
    }

    func testAllRPMRulesAreCheckedAndRedLineWithoutFillStillHasBounds() {
        var config = config()
        config.rules.append(.range(.init(action: "custom", signalKey: "vehicle.engine_rpm",
                                         input: .init(from: 2000, to: 1000), output: .init(from: 0, to: 1))))
        XCTAssertTrue(RPMValidation.issues(in: config).contains { $0.ruleIndex == 2 && $0.problem == .rangeOrder })
        config.rules = [.sampledState(.init(action: "red_zone", signalKey: "vehicle.engine_rpm",
                                            comparison: .greater, operand: .number(12001)))]
        XCTAssertTrue(RPMValidation.issues(in: config).contains { $0.problem == .outsideBounds })
    }
}
