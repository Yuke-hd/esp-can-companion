import XCTest
import CompanionProtocol
@testable import CANCompanion

final class RuleConfigEditingTests: XCTestCase {
    private let zone = ControllerConfig.ZoneBinding(
        action: "shift", zone: .init(start: 20, length: 10, direction: .centerOut),
        color: .init(red: 0, green: 32, blue: 0), priority: 150)

    func testAddedRuleGetsItsOwnActionAndASolidEffect() {
        var config = ControllerConfig(actions: [.init(name: "custom_1")])
        let index = config.addCustomRule()

        XCTAssertEqual(index, 0)
        XCTAssertEqual(config.actions.map(\.name), ["custom_1", "custom_2"])
        XCTAssertEqual(config.rules[index].action, "custom_2")
        XCTAssertEqual(config.outputs, [.solid(for: "custom_2")])
    }

    func testRemovingTheLastRuleForAnActionAlsoRemovesItsActionAndOutputs() {
        let rule = ControllerConfig.Rule.state(.init(action: "shift", signalKey: "vehicle.engine_rpm",
                                                     comparison: .greater, operand: .number(6000)))
        var config = ControllerConfig(actions: [.init(name: "shift")], rules: [rule, rule], outputs: [.ledSolid(zone)])

        config.removeRule(at: 0)
        XCTAssertEqual(config.rules.count, 1)
        XCTAssertEqual(config.outputs.count, 1, "Another rule still uses the action.")

        config.removeRule(at: 0)
        XCTAssertEqual(config, ControllerConfig())
    }

    func testConvertingAnEffectKeepsItsZoneColourAndPriority() {
        let flash = ControllerConfig.OutputBinding.ledSolid(zone).converted(to: .flash)
        XCTAssertEqual(flash, .ledTransient(zone, durationMs: ControllerConfig.OutputBinding.defaultFlashMs))
        XCTAssertEqual(flash.converted(to: .fill), .ledFill(zone))

        let builtIn = flash.converted(to: .builtIn)
        XCTAssertEqual(builtIn, .ledEffect(.init(action: "shift", effect: .brake, priority: 150)))
        let solid = builtIn.converted(to: .solid)
        XCTAssertEqual(solid.priority, 150)
        XCTAssertEqual(solid.zoneBinding?.zone, ControllerConfig.OutputBinding.defaultZone)
    }

    func testReplacingPriorityKeepsTheEffectKind() {
        XCTAssertEqual(ControllerConfig.OutputBinding.ledTransient(zone, durationMs: 400).replacingPriority(90).effectKind, .flash)
        XCTAssertEqual(ControllerConfig.OutputBinding.ledEffect(.init(action: "a", effect: .leftTurn)).replacingPriority(90).priority, 90)
    }
}

final class ActionRenameTests: XCTestCase {
    private let zone = ControllerConfig.ZoneBinding(
        action: "shift", zone: .init(start: 0, length: 4, direction: .startToEnd), color: .init(red: 1, green: 2, blue: 3))

    private var config: ControllerConfig {
        ControllerConfig(
            actions: [.init(name: "shift"), .init(name: "brake")],
            rules: [.sampledState(.init(action: "shift", signalKey: "vehicle.engine_rpm", comparison: .greater,
                                        operand: .number(6000)), releaseThreshold: 5800),
                    .range(.init(action: "shift", signalKey: "vehicle.engine_rpm", input: .init(from: 1, to: 2),
                                 output: .init(from: 0, to: 1)))],
            outputs: [.ledTransient(zone, durationMs: 300), .ledEffect(.init(action: "brake", effect: .brake))])
    }

    func testRenameUpdatesTheActionItsRulesAndItsOutputs() throws {
        var renamed = config
        try renamed.renameAction("shift", to: "  Shift Light! ")

        XCTAssertEqual(renamed.actions.map(\.name), ["shift_light", "brake"])
        XCTAssertEqual(renamed.rules.map(\.action), ["shift_light", "shift_light"])
        XCTAssertEqual(renamed.outputs.map(\.action), ["shift_light", "brake"])
        XCTAssertEqual(renamed.outputs[0].effectKind, .flash)
        if case .sampledState(_, let release) = renamed.rules[0] { XCTAssertEqual(release, 5800) } else { XCTFail() }
    }

    func testRenameRejectsEmptyAndTakenNames() {
        var renamed = config
        XCTAssertThrowsError(try renamed.renameAction("shift", to: " -- ")) {
            XCTAssertEqual($0 as? ControllerConfig.RenameError, .empty)
        }
        XCTAssertThrowsError(try renamed.renameAction("shift", to: "Brake")) {
            XCTAssertEqual($0 as? ControllerConfig.RenameError, .taken)
        }
        XCTAssertNoThrow(try renamed.renameAction("shift", to: "SHIFT"))
        XCTAssertEqual(renamed, config)
    }

    func testRenameKeepsBuiltInActionNames() {
        var renamed = config
        renamed.actions.append(.init(name: "red_zone"))
        renamed.rules.append(.state(.init(action: "red_zone", signalKey: "vehicle.engine_rpm", comparison: .greaterOrEqual,
                                          operand: .number(7000), freshness: .freshOrUnverified)))
        let before = renamed
        XCTAssertThrowsError(try renamed.renameAction("red_zone", to: "Shift light")) {
            XCTAssertEqual($0 as? ControllerConfig.RenameError, .reserved)
        }
        XCTAssertThrowsError(try renamed.renameAction("shift", to: "RPM fill")) {
            XCTAssertEqual($0 as? ControllerConfig.RenameError, .reserved)
        }
        XCTAssertEqual(renamed, before)
    }

    func testActionNamesKeepOnlyASCIILettersAndNumbers() {
        XCTAssertEqual(ControllerConfig.actionName(from: "Café 2"), "caf_2")
    }
}
