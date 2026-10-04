import XCTest
import CompanionProtocol
@testable import PresetSync

final class PresetCatalogTests: XCTestCase {
    private let brakeSignal = "vehicle.brake_pressed"

    func testBundledPresetsLoad() throws {
        let presets = try PresetCatalog.bundled()
        XCTAssertEqual(presets.map(\.id), ["early-shift", "track", "calm"])
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
        for preset in presets {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertFalse(preset.summary.isEmpty)
            XCTAssertEqual(preset.config.version, 1, preset.id)
        }
    }

    /// The upload encodes `Preset.config`; it must produce exactly the
    /// canonical document that ships in the bundle.
    func testPresetsEncodeToTheirCanonicalDocument() throws {
        for preset in try PresetCatalog.bundled() {
            let encoded = try preset.config.encodedJSON()
            XCTAssertEqual(
                String(decoding: encoded, as: UTF8.self),
                String(decoding: try PresetCatalog.resource("\(preset.id).json"), as: UTF8.self),
                preset.id
            )
            XCTAssertEqual(try ControllerConfig(canonicalJSON: encoded), preset.config, preset.id)
        }
    }

    func testFactoryMatchesTheFirmwareProfile() throws {
        let factory = try PresetCatalog.factory()
        XCTAssertEqual(factory.actions.map(\.name), ["left_turn", "right_turn", "hazard", "rpm_fill", "red_zone", "brake"])
        // The firmware file ends with a newline; the canonical form does not.
        let document = try PresetCatalog.resource("factory.json")
        XCTAssertEqual(document.last, UInt8(ascii: "\n"))
        XCTAssertEqual(try factory.encodedJSON(), document.dropLast())
    }

    func testPresetsDifferFromFactory() throws {
        let factory = try PresetCatalog.factory()
        for preset in try PresetCatalog.bundled() {
            XCTAssertNotEqual(preset.config, factory, preset.id)
        }
    }

    /// Safety invariant from #5: the brake light keeps the factory's
    /// owner-approved rule, a Boolean `state` rule with `fresh_or_unverified`
    /// on `vehicle.brake_pressed`, and its factory output. No other rule reads
    /// the brake signal.
    func testBrakeLightIsTheFactoryOne() throws {
        let factory = try PresetCatalog.factory()
        let factoryBrakeRules = factory.rules.filter { $0.action == "brake" }
        XCTAssertEqual(factoryBrakeRules, [.state(.init(
            action: "brake", signalKey: brakeSignal, comparison: .equal,
            operand: .boolean(true), freshness: .freshOrUnverified
        ))])
        for preset in try PresetCatalog.bundled() {
            let config = preset.config
            XCTAssertEqual(config.rules.filter { $0.action == "brake" }, factoryBrakeRules, preset.id)
            XCTAssertEqual(
                config.outputs.filter { $0.action == "brake" },
                factory.outputs.filter { $0.action == "brake" },
                preset.id
            )
            let brakeSignalRules = config.rules.filter { signalKey(of: $0) == brakeSignal }
            XCTAssertEqual(brakeSignalRules, factoryBrakeRules, "\(preset.id) reads the brake signal elsewhere")
        }
    }

    func testTurnSignalsAndHazardsAreTheFactoryOnes() throws {
        let factory = try PresetCatalog.factory()
        let actions: Set = ["left_turn", "right_turn", "hazard"]
        for preset in try PresetCatalog.bundled() {
            XCTAssertEqual(
                preset.config.rules.filter { actions.contains($0.action) },
                factory.rules.filter { actions.contains($0.action) },
                preset.id
            )
            XCTAssertEqual(
                preset.config.outputs.filter { actions.contains($0.action) },
                factory.outputs.filter { actions.contains($0.action) },
                preset.id
            )
        }
    }

    func testRulesAndOutputsReferToDeclaredActions() throws {
        for preset in try PresetCatalog.bundled() {
            let declared = Set(preset.config.actions.map(\.name))
            XCTAssertEqual(declared.count, preset.config.actions.count, preset.id)
            for name in preset.config.rules.map(\.action) + preset.config.outputs.map(\.action) {
                XCTAssertTrue(declared.contains(name), "\(preset.id): \(name)")
            }
        }
    }

    private func signalKey(of rule: ControllerConfig.Rule) -> String {
        switch rule {
        case .state(let condition), .sampledState(let condition, _), .event(let condition, _): condition.signalKey
        case .range(let range): range.signalKey
        }
    }
}
