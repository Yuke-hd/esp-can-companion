import XCTest
import CompanionProtocol
import PresetSync
@testable import CompanionLink

final class ConfigSummaryTests: XCTestCase {
    func testFactoryConfigInPlainLanguage() throws {
        let config = try ControllerConfig(canonicalJSON: DemoController.factoryDocument)
        let summary = ConfigSummary(config)
        let byName = Dictionary(uniqueKeysWithValues: summary.actions.map { ($0.name, $0) })

        XCTAssertEqual(byName["left_turn"]?.title, "Left turn")
        XCTAssertEqual(byName["left_turn"]?.triggers, ["When turn state is left"])
        XCTAssertEqual(byName["left_turn"]?.outputs, ["Right turn LED effect"])
        XCTAssertEqual(byName["hazard"]?.outputs, ["Left turn LED effect", "Right turn LED effect"])
        XCTAssertEqual(byName["rpm_fill"]?.triggers, ["Follows engine rpm from 0 to 6500"])
        XCTAssertEqual(byName["rpm_fill"]?.outputs, ["Fills LEDs 0–99 from the center out"])
        XCTAssertEqual(byName["red_zone"]?.triggers, ["When engine rpm is above 6000, checked periodically"])
        XCTAssertEqual(byName["red_zone"]?.outputs, ["Lights LEDs 35–64"])
        XCTAssertEqual(byName["brake"]?.triggers, ["When brake pressed is on"])
    }

    func testOtherRuleAndOutputShapes() {
        let config = ControllerConfig(
            actions: [.init(name: "door_chime"), .init(name: "shift")],
            rules: [
                .event(.init(action: "door_chime", signalKey: "vehicle.door.front_left_open", comparison: .equal, operand: .boolean(false)), edge: .becomesTrue),
                .sampledState(.init(action: "shift", signalKey: "vehicle.engine_rpm", comparison: .greaterOrEqual, operand: .number(5800.5)), releaseThreshold: 5500),
            ],
            outputs: [
                .ledTransient(.init(action: "door_chime", zone: .init(start: 7, length: 1, direction: .startToEnd), color: .init(red: 1, green: 1, blue: 1)), durationMs: 250),
            ]
        )
        let summary = ConfigSummary(config)
        XCTAssertEqual(summary.actions[0].triggers, ["Each time door front left open is off starts"])
        XCTAssertEqual(summary.actions[0].outputs, ["Flashes LED 7 for 250 ms"])
        XCTAssertEqual(summary.actions[1].triggers, ["When engine rpm is at least 5800.5, checked periodically, releases at 5500"])
        XCTAssertEqual(summary.actions[1].outputs, [])
    }

    func testOutputStackByPriority() throws {
        let config = try ControllerConfig(canonicalJSON: DemoController.factoryDocument)
        let stack = ConfigSummary(config).outputStack
        // Hazard's two effects show once; equal priorities keep config order.
        XCTAssertEqual(stack.map(\.title), ["Brake", "Red zone", "Left turn", "Right turn", "Hazard", "Rpm fill"])
        XCTAssertEqual(stack.map(\.priority), [200, 150, 100, 100, 100, 50])
        XCTAssertEqual(stack.map(\.kind), [.solid, .solid, .effect, .effect, .effect, .fill])
        XCTAssertEqual(stack[0].color, .init(red: 16, green: 0, blue: 0))
        XCTAssertNil(stack[2].color)
    }

    func testRPMBand() throws {
        let factory = ConfigSummary(try ControllerConfig(canonicalJSON: DemoController.factoryDocument))
        XCTAssertEqual(factory.rpmBand.fill, .init(from: 0, to: 6500))
        XCTAssertEqual(factory.rpmBand.redline, 6000)

        let custom = ConfigSummary(try ControllerConfig(canonicalJSON: DemoController.customDocument))
        XCTAssertNil(custom.rpmBand.fill)
        XCTAssertEqual(custom.rpmBand.redline, 5800)
    }

    func testProfile() throws {
        let factory = try ControllerConfig(canonicalJSON: DemoController.factoryDocument)
        let track = Preset(id: "track", name: "Track", summary: "", config: ControllerConfig(actions: [.init(name: "brake")]))
        XCTAssertEqual(ConfigSummary.profile(of: factory, factory: factory, presets: [track]), .factory)
        XCTAssertEqual(ConfigSummary.profile(of: track.config, factory: factory, presets: [track]), .preset("Track"))
        XCTAssertEqual(ConfigSummary.profile(of: ControllerConfig(), factory: factory, presets: [track]), .custom)
    }
}
