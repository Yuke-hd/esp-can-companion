import XCTest
@testable import CompanionProtocol

final class ControllerConfigTests: XCTestCase {
    func testEveryRuleAndOutputKindRoundTrips() throws {
        let config = ControllerConfig(
            actions: [.init(name: "red_zone"), .init(name: "door_open"), .init(name: "brake"), .init(name: "speed")],
            rules: [
                .sampledState(
                    .init(action: "red_zone", signalKey: "vehicle.engine_rpm", comparison: .greater,
                          operand: .number(6000), freshness: .freshOrUnverified),
                    releaseThreshold: 5800.5
                ),
                .event(
                    .init(action: "door_open", signalKey: "vehicle.door.rear_left", comparison: .equal, operand: .boolean(true)),
                    edge: .becomesTrue
                ),
                .state(.init(action: "brake", signalKey: "vehicle.turn_state", comparison: .notEqual, operand: .choice("off"))),
                .range(.init(action: "speed", signalKey: "vehicle.speed_kph",
                             input: .init(from: 0, to: 120), output: .init(from: 1, to: 0.25))),
            ],
            outputs: [
                .ledEffect(.init(action: "brake", effect: .brake)),
                .ledFill(.init(action: "speed", zone: .init(start: 0, length: 100, direction: .centerOut),
                               color: .init(red: 0, green: 16, blue: 32), priority: 50)),
                .ledTransient(.init(action: "door_open", zone: .init(start: 20, length: 20, direction: .startToEnd),
                                    color: .init(red: 32, green: 16, blue: 0), priority: 120), durationMs: 800),
                .ledSolid(.init(action: "red_zone", zone: .init(start: 35, length: 30, direction: .endToStart),
                                color: .init(red: 16, green: 0, blue: 0), priority: 150)),
            ]
        )
        let encoded = try config.encodedJSON()
        XCTAssertEqual(try ControllerConfig(canonicalJSON: encoded), config)

        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(json.contains(#""release_threshold":5800.5"#), json)
        XCTAssertTrue(json.contains(#""edge":"becomes_true""#), json)
        XCTAssertTrue(json.contains(#""duration_ms":800"#), json)
        XCTAssertTrue(json.contains(#""type":"led_transient""#), json)
        XCTAssertTrue(json.contains(#""operand":{"choice":"off"}"#), json)
        XCTAssertTrue(json.contains(#""comparison":"not_equal""#), json)
    }

    func testOmittedFieldsTakeSpecDefaults() throws {
        let json = """
        {"version":1,"rules":[{"type":"state","action":"a","signal_key":"vehicle.turn_state",
        "comparison":"equal","operand":{"choice":"left"}}],
        "outputs":[{"type":"led_effect","action":"a","effect":"left_turn"}]}
        """
        let config = try ControllerConfig(canonicalJSON: Data(json.utf8))
        XCTAssertEqual(config.actions, [])
        guard case .state(let condition) = config.rules.first else { return XCTFail("Expected a state rule") }
        XCTAssertEqual(condition.freshness, .fresh)
        XCTAssertEqual(config.outputs.first, .ledEffect(.init(action: "a", effect: .leftTurn, priority: 100)))
    }

    func testOperandMustHaveExactlyOneKey() {
        let json = """
        {"version":1,"rules":[{"type":"state","action":"a","signal_key":"k",
        "comparison":"equal","operand":{"boolean":true,"number":1}}]}
        """
        XCTAssertThrowsError(try ControllerConfig(canonicalJSON: Data(json.utf8)))
    }

    func testUnknownNamesAreRejected() {
        for json in [
            #"{"version":1,"rules":[{"type":"toggle","action":"a","signal_key":"k"}]}"#,
            #"{"version":1,"outputs":[{"type":"wled","action":"a"}]}"#,
            #"{"version":1,"rules":[{"type":"state","action":"a","signal_key":"k","comparison":"about","operand":{"number":1}}]}"#,
        ] {
            XCTAssertThrowsError(try ControllerConfig(canonicalJSON: Data(json.utf8)), json)
        }
    }

    func testPersistedNamesMatchTheSpec() {
        XCTAssertEqual(ControllerConfig.Comparison.allCases.map(\.rawValue),
                       ["equal", "not_equal", "less", "less_or_equal", "greater", "greater_or_equal"])
        XCTAssertEqual(ControllerConfig.Freshness.allCases.map(\.rawValue), ["fresh", "fresh_or_unverified"])
        XCTAssertEqual(ControllerConfig.EventEdge.allCases.map(\.rawValue), ["becomes_true", "becomes_false"])
        XCTAssertEqual(ControllerConfig.LedEffect.allCases.map(\.rawValue), ["left_turn", "right_turn", "brake"])
        XCTAssertEqual(ControllerConfig.FillDirection.allCases.map(\.rawValue), ["start_to_end", "end_to_start", "center_out"])
    }

    func testZoneLastPixelUsesCheckedArithmetic() {
        func zone(_ start: Int, _ length: Int) -> ControllerConfig.Zone {
            .init(start: start, length: length, direction: .startToEnd)
        }

        XCTAssertEqual(zone(0, 1).lastPixel, 0)
        XCTAssertEqual(zone(Int.max - 29, 30).lastPixel, Int.max)
        XCTAssertNil(zone(Int.max, 30).lastPixel)
        XCTAssertNil(zone(2, Int.max).lastPixel)
        XCTAssertNil(zone(0, 0).lastPixel)
        XCTAssertNil(zone(0, -1).lastPixel)
    }
}
