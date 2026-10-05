import XCTest
import CompanionProtocol
@testable import PresetSync

final class ConfigTweaksTests: XCTestCase {
    func testChangingRPMRangePreservesAllOtherRulesOutputsAndFreshness() throws {
        let original = try PresetCatalog.bundled()[0].config
        let changed = ConfigTweaks(config: original)
            .settingRPMInputRange(RPMInputRange(lower: 1_200, upper: 6_400)).config
        XCTAssertEqual(changed.actions, original.actions)
        XCTAssertEqual(changed.outputs, original.outputs)
        XCTAssertEqual(changed.rules.filter { $0.action != "rpm_fill" }, original.rules.filter { $0.action != "rpm_fill" })
        guard case .range(let before) = try XCTUnwrap(original.rules.first { $0.action == "rpm_fill" }),
              case .range(let after) = try XCTUnwrap(changed.rules.first { $0.action == "rpm_fill" }) else {
            return XCTFail("RPM fill remains a range rule")
        }
        XCTAssertEqual(after.input, .init(from: 1_200, to: 6_400))
        XCTAssertEqual(after.freshness, before.freshness)
        XCTAssertEqual(after.signalKey, before.signalKey)
        XCTAssertEqual(after.output, before.output)
    }

    func testRedZoneThresholdEditsPreserveTheSampledCondition() throws {
        let original = try PresetCatalog.bundled()[1].config
        let changed = ConfigTweaks(config: original)
            .settingRedZoneThresholds(RedZoneThresholds(triggerAbove: 6_000, releaseBelow: 5_800)).config
        guard case .sampledState(let before, _) = try XCTUnwrap(original.rules.first { $0.action == "red_zone" }),
              case .sampledState(let after, let release) = try XCTUnwrap(changed.rules.first { $0.action == "red_zone" }) else {
            return XCTFail("Red zone remains sampled state")
        }
        XCTAssertEqual(after.operand, .number(6_000))
        XCTAssertEqual(release, 5_800)
        XCTAssertEqual(after.signalKey, before.signalKey)
        XCTAssertEqual(after.freshness, before.freshness)
        XCTAssertEqual(after.comparison, before.comparison)
        XCTAssertEqual(changed.outputs, original.outputs)
    }

    func testBrakeOutputEditsPreserveTheFactoryBrakeRuleAndOtherBindings() throws {
        let original = try PresetCatalog.bundled()[0].config
        let settings = ActionOutputSettings(color: .init(red: 16, green: 0, blue: 4),
                                            zone: .init(start: 20, length: 40, direction: .centerOut), priority: 220)
        let tweaks = ConfigTweaks(config: original).settingOutput(settings, for: .brake)
        XCTAssertEqual(tweaks.output(for: .brake), settings)
        XCTAssertEqual(tweaks.config.rules, original.rules)
        XCTAssertEqual(tweaks.config.outputs.filter { $0.action != "brake" }, original.outputs.filter { $0.action != "brake" })
        guard case .ledSolid = try XCTUnwrap(tweaks.config.outputs.first { $0.action == "brake" }) else {
            return XCTFail("Brake output remains solid")
        }
    }

    func testCalmDoesNotGainRPMRulesWhenUnavailableControlsAreUpdated() throws {
        let original = try PresetCatalog.bundled()[2].config
        let tweaks = ConfigTweaks(config: original)
        XCTAssertNil(tweaks.rpmInputRange)
        XCTAssertNil(tweaks.redZoneThresholds)
        XCTAssertNil(tweaks.output(for: .rpmFill))
        XCTAssertEqual(tweaks.settingRPMInputRange(.init(lower: 1_000, upper: 6_500)).config, original)
        XCTAssertEqual(tweaks.settingRedZoneThresholds(.init(triggerAbove: 6_000, releaseBelow: 5_800)).config, original)
    }

    func testTransientOutputSettingsPreserveTheDuration() {
        let original = ControllerConfig(outputs: [.ledTransient(.init(action: "brake", zone: .init(start: 0, length: 20, direction: .startToEnd), color: .init(red: 16, green: 0, blue: 0)), durationMs: 350)])
        let settings = ActionOutputSettings(color: .init(red: 4, green: 0, blue: 0), zone: .init(start: 3, length: 10, direction: .endToStart), priority: 250)
        let updated = ConfigTweaks(config: original).settingOutput(settings, for: .brake)
        guard case .ledTransient(_, let duration) = updated.config.outputs[0] else { return XCTFail("Transient output stays transient") }
        XCTAssertEqual(duration, 350)
    }
    func testReferenceControlsAreUnavailableAfterIncompatibleFullRuleEdits() {
        let config = ControllerConfig(rules: [
            .range(.init(action: "rpm_fill", signalKey: "vehicle.speed_kph", input: .init(from: 0, to: 100), output: .init(from: 0, to: 1))),
            .sampledState(.init(action: "red_zone", signalKey: "vehicle.engine_rpm", comparison: .less, operand: .number(2_000)))
        ])
        let tweaks = ConfigTweaks(config: config)
        XCTAssertNil(tweaks.rpmInputRange)
        XCTAssertNil(tweaks.redZoneThresholds)
        XCTAssertEqual(tweaks.settingRPMInputRange(.init(lower: 1_000, upper: 6_500)).config, config)
        XCTAssertEqual(tweaks.settingRedZoneThresholds(.init(triggerAbove: 6_000, releaseBelow: 5_800)).config, config)
    }

    func testChangeCountIncludesFullEditorActionsRulesOutputsAndVersion() {
        let original = ControllerConfig(actions: [.init(name: "brake")], rules: [.state(.init(action: "brake", signalKey: "vehicle.brake_pressed", comparison: .equal, operand: .boolean(true)))])
        var edited = original
        edited.actions.append(.init(name: "extra"))
        edited.rules.removeAll()
        edited.outputs.append(.ledEffect(.init(action: "extra", effect: .leftTurn)))
        edited.version = 2
        XCTAssertEqual(ConfigTweaks(config: edited).changeCount(from: original), 4)
        XCTAssertEqual(ConfigTweaks(config: original).changeCount(from: original), 0)
    }

    func testRemovingFirstRuleCountsOneChangeRatherThanEveryShiftedRule() throws {
        let original = try PresetCatalog.bundled()[0].config
        var edited = original
        edited.rules.removeFirst()
        XCTAssertEqual(ConfigTweaks(config: edited).changeCount(from: original), 1)
    }

}
