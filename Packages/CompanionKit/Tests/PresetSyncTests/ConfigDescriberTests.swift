import XCTest
import CompanionProtocol
@testable import PresetSync

final class ConfigDescriberTests: XCTestCase {
    func testDescribesTheFactoryProfile() throws {
        let descriptions = ConfigDescriber.describe(try PresetCatalog.factory())
        let byID = Dictionary(uniqueKeysWithValues: descriptions.map { ($0.id, $0) })
        XCTAssertEqual(descriptions.map(\.title), ["Left turn", "Right turn", "Hazard", "RPM fill", "Red zone", "Brake"])
        XCTAssertEqual(byID["left_turn"]?.detail, "Runs the right-turn LED effect while the turn signal is left.")
        XCTAssertEqual(
            byID["hazard"]?.detail,
            "Runs the left-turn LED effect and runs the right-turn LED effect while the turn signal is on hazards."
        )
        XCTAssertEqual(
            byID["rpm_fill"]?.detail,
            "Fills pixels 0–99 from the centre out in blue in proportion to engine speed from 0 rpm to 6,500 rpm."
                + " It also acts on readings the controller cannot confirm are fresh."
        )
        XCTAssertEqual(
            byID["red_zone"]?.detail,
            "Lights pixels 35–64 solid red while engine speed is above 6,000 rpm."
                + " It also acts on readings the controller cannot confirm are fresh."
        )
        XCTAssertEqual(
            byID["brake"]?.detail,
            "Lights pixels 35–64 solid red while the brake pedal is pressed."
                + " It also acts on readings the controller cannot confirm are fresh."
        )
    }

    func testEveryPresetActionHasADescription() throws {
        for preset in try PresetCatalog.bundled() {
            XCTAssertEqual(preset.actionDescriptions.map(\.id), preset.config.actions.map(\.name))
            for description in preset.actionDescriptions {
                XCTAssertFalse(description.detail.isEmpty)
                XCTAssertFalse(description.detail.contains("No rule"), "\(preset.id): \(description.id)")
            }
        }
    }

    func testOtherRuleAndOutputKinds() {
        let condition = ControllerConfig.Condition(
            action: "door", signalKey: "vehicle.door_open", comparison: .equal, operand: .boolean(true)
        )
        let zone = ControllerConfig.Zone(start: 3, length: 1, direction: .endToStart)
        let config = ControllerConfig(
            actions: [.init(name: "door"), .init(name: "idle")],
            rules: [.event(condition, edge: .becomesTrue)],
            outputs: [.ledTransient(.init(action: "door", zone: zone, color: .init(red: 0, green: 40, blue: 0)), durationMs: 500)]
        )
        let descriptions = ConfigDescriber.describe(config)
        XCTAssertEqual(
            descriptions[0].detail,
            "Lights pixel 3 green for 500 ms briefly each time vehicle.door_open is true starts to hold."
        )
        XCTAssertEqual(descriptions[1].detail, "Shows nothing. No rule turns it on.")
    }

    func testDescribesZonesWithUnrepresentableEndpointsWithoutOverflowing() {
        func detail(start: Int, length: Int) -> String? {
            let zone = ControllerConfig.Zone(start: start, length: length, direction: .startToEnd)
            let config = ControllerConfig(
                actions: [.init(name: "brake")],
                outputs: [.ledSolid(.init(action: "brake", zone: zone, color: .init(red: 255, green: 0, blue: 0)))]
            )
            return ConfigDescriber.describe(config).first?.detail
        }

        XCTAssertEqual(
            detail(start: Int.max, length: 30),
            "Lights LEDs starting at \(Int.max) for 30 pixels solid red. No rule turns it on."
        )
        XCTAssertEqual(
            detail(start: 2, length: Int.max),
            "Lights LEDs starting at 2 for \(Int.max) pixels solid red. No rule turns it on."
        )
        XCTAssertEqual(
            detail(start: 0, length: 0),
            "Lights LED zone starting at 0 with invalid length 0 solid red. No rule turns it on."
        )
    }

    func testColorNames() {
        func name(_ red: Int, _ green: Int, _ blue: Int) -> String {
            ConfigDescriber.colorName(.init(red: red, green: green, blue: blue))
        }
        XCTAssertEqual(name(16, 0, 0), "red")
        XCTAssertEqual(name(0, 24, 0), "green")
        XCTAssertEqual(name(0, 16, 32), "blue")
        XCTAssertEqual(name(32, 16, 0), "orange")
        XCTAssertEqual(name(20, 20, 20), "white")
        XCTAssertEqual(name(0, 0, 0), "black (off)")
    }

    func testNumbersAreGrouped() {
        XCTAssertEqual(ConfigDescriber.grouped(0), "0")
        XCTAssertEqual(ConfigDescriber.grouped(650), "650")
        XCTAssertEqual(ConfigDescriber.grouped(6500), "6,500")
        XCTAssertEqual(ConfigDescriber.grouped(-1_234_567), "-1,234,567")
        XCTAssertEqual(ConfigDescriber.number(2.5, signal: "vehicle.engine_rpm"), "2.5 rpm")
    }
}
