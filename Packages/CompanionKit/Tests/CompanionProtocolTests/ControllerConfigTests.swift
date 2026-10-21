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
            #"{"version":1,"rules":[{"type":"state","action":"a","signal_key":"k","comparison":"about","operand":{"number":1}}]}"#,
        ] {
            XCTAssertThrowsError(try ControllerConfig(canonicalJSON: Data(json.utf8)), json)
        }
    }

    func testUnknownOutputContentAndSinkSettingsRoundTrip() throws {
        let json = #"{"version":1,"actions":[],"rules":[],"outputs":[{"type":"future_output","action":"future","vendor":{"mode":"fast"}},{"type":"led_effect","action":"brake","effect":"future_effect","priority":100,"extra":7},{"type":"led_fill","action":"rpm_fill","zone":{"start":0,"length":20,"direction":"future_direction"},"color":{"red":1,"green":2,"blue":3},"priority":4},{"type":"led_fill","action":"known","zone":{"start":0,"length":5,"direction":"start_to_end","vendor_zone":true},"color":{"red":1,"green":2,"blue":3,"vendor_color":"keep"},"priority":5,"vendor_key":{"enabled":true}}],"sinks":{"local_argb":{"pixel_count":175,"vendor":"keep"}}}"#
        let config = try ControllerConfig(canonicalJSON: Data(json.utf8))
        let encoded = try config.encodedJSON()
        let encodedJSON = String(decoding: encoded, as: UTF8.self)
        for preserved in [
            #""type":"future_output""#, #""effect":"future_effect""#,
            #""direction":"future_direction""#, #""vendor":{"mode":"fast"}"#,
            #""vendor_key":{"enabled":true}"#, #""pixel_count":175"#,
            #""vendor":"keep""#, #""vendor_zone":true"#,
            #""vendor_color":"keep""#,
        ] {
            XCTAssertTrue(encodedJSON.contains(preserved), "Missing \(preserved) in \(encodedJSON)")
        }
        XCTAssertEqual(try ControllerConfig(canonicalJSON: encoded), config)
    }

    func testFieldsRecognizedByOtherOutputKindsArePreserved() throws {
        let zone = #""zone":{"start":0,"length":1,"direction":"start_to_end"},"color":{"red":1,"green":2,"blue":3}"#
        let inputs = [
            #"{"type":"led_effect","action":"a","priority":100,"effect":"brake","zone":{"future":true},"color":"future","duration_ms":17}"#,
            "{\"type\":\"led_fill\",\"action\":\"a\",\"priority\":100,\(zone),\"effect\":\"future\",\"duration_ms\":17}",
            "{\"type\":\"led_solid\",\"action\":\"a\",\"priority\":100,\(zone),\"effect\":\"future\",\"duration_ms\":17}",
            "{\"type\":\"led_transient\",\"action\":\"a\",\"priority\":100,\(zone),\"effect\":\"future\",\"duration_ms\":17}",
        ]
        for input in inputs {
            let source = Data(input.utf8)
            let binding = try JSONDecoder().decode(ControllerConfig.OutputBinding.self, from: source)
            let encoded = try JSONEncoder().encode(binding)
            XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: source),
                           try JSONDecoder().decode(JSONValue.self, from: encoded), input)
        }
    }

    func testOpaqueIntegerValuesMatchSourceAfterEncoding() throws {
        for integer in ["9007199254740993", "9223372036854775807", "9223372036854775808", "18446744073709551615", "-9007199254740993"] {
            let source = "{\"version\":1,\"outputs\":[{\"type\":\"future\",\"counter\":\(integer)}],\"sinks\":{\"future\":{\"counter\":\(integer)}}}"
            let config = try ControllerConfig(canonicalJSON: Data(source.utf8))
            let encoded = String(decoding: try config.encodedJSON(), as: UTF8.self)
            XCTAssertEqual(encoded.components(separatedBy: "\"counter\":\(integer)").count - 1, 2, encoded)
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
