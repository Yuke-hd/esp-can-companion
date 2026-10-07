import XCTest
import BLETransport
import CompanionProtocol
import CompanionLink
@testable import CANCompanion

final class MotorsportDriveTextTests: XCTestCase {
    private func readout(_ change: (inout DemoTelemetry) -> Void = { _ in }) throws -> DriveReadout {
        var telemetry = DemoTelemetry()
        change(&telemetry)
        let frame = try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: telemetry.layoutVersion)
        return DriveReadout(frame: frame, linkState: .connected(.init(
            id: UUID(), name: "Demo Controller", maximumWriteLength: 182
        )))
    }

    func testGearAccessibilityCombinesGearSelectorAndFreshness() throws {
        let value = try readout {
            $0.actualGear = .fourth
            $0.selectorPosition = .drive
        }

        XCTAssertEqual(value.gearAccessibilityText, "Gear 4, Drive, Unverified")
    }

    func testStaleAndStalledMetricsUsePlaceholders() throws {
        let stale = try readout {
            $0.statuses[0] = .stale
            $0.statuses[1] = .stale
            $0.statuses[4] = .stale
        }
        let stalled = DriveReadout(frame: .unknown)

        for value in [stale, stalled] {
            XCTAssertEqual(value.rpmDisplayText, "—")
            XCTAssertEqual(value.speedDisplayText, "—")
            XCTAssertEqual(value.gearDisplayText, "—")
            XCTAssertEqual(value.selectorDisplayText, "—")
        }
    }

    func testBrakeAndTurnTextRetainSignalFreshness() throws {
        let value = try readout {
            $0.booleans = 1 << 12
            $0.turnState = .left
        }

        XCTAssertEqual(value.brakeAccessibilityText, "Brake, Pressed, Unverified")
        XCTAssertEqual(value.turnAccessibilityText, "Turn, Left, Fresh")
    }

    func testUnsupportedInputsAreInactivePlaceholders() throws {
        let value = try readout()

        XCTAssertEqual(value.throttleDisplayText, "NO SIGNAL")
        XCTAssertEqual(value.throttleAccessibilityText, "Throttle, Not supported")

        let stalled = DriveReadout(frame: .unknown)
        XCTAssertEqual(stalled.throttleDisplayText, "UNKNOWN")
    }

    // MARK: G-meter

    func testGMeterLiveTextNamesEachDirection() throws {
        let value = try readout {
            $0.longitudinalAcceleration = -4
            $0.lateralAcceleration = 7
        }
        // Text follows the smoothed value the meter shows, not the raw sample.
        let smoothed = GForce(longitudinal: -0.42, lateral: 0.71)

        XCTAssertNil(value.gMeterStatusText)
        XCTAssertEqual(value.gMeterValueText(smoothed), "0.8")
        XCTAssertEqual(value.gMeterAccessibilityText(smoothed), "G-meter, 0.4 g braking, 0.7 g right")
    }

    func testGMeterAccessibilityNamesAccelerationAndLeft() throws {
        let value = try readout {
            $0.longitudinalAcceleration = 3
            $0.lateralAcceleration = -5
        }

        XCTAssertEqual(
            value.gMeterAccessibilityText(GForce(longitudinal: 0.3, lateral: -0.5)),
            "G-meter, 0.3 g accelerating, 0.5 g left"
        )
        // A component that rounds to zero is left out rather than read as "0.0 g left".
        XCTAssertEqual(
            value.gMeterAccessibilityText(GForce(longitudinal: 0.21, lateral: -0.02)),
            "G-meter, 0.2 g accelerating"
        )
        XCTAssertEqual(value.gMeterAccessibilityText(GForce(longitudinal: 0.01, lateral: -0.04)), "G-meter, 0.0 g")
        XCTAssertEqual(value.gMeterValueText(GForce(longitudinal: -0.01, lateral: 0.02)), "0.0")
    }

    func testGMeterSpokenTotalMatchesVisibleNumberWhenComponentsRoundToZero() throws {
        let value = try readout {
            $0.longitudinalAcceleration = 0.4
            $0.lateralAcceleration = 0.4
        }
        // Each axis rounds to 0.0 but the total shown under the dial is 0.1;
        // the label must not contradict the visible number.
        let small = GForce(longitudinal: 0.04, lateral: 0.04)
        XCTAssertEqual(value.gMeterValueText(small), "0.1")
        XCTAssertEqual(value.gMeterAccessibilityText(small), "G-meter, 0.1 g")
    }

    func testGMeterRoundingBoundaryAtFiveHundredths() throws {
        let value = try readout {
            $0.longitudinalAcceleration = 0.5
            $0.lateralAcceleration = 0
        }
        // Pins current one-decimal rounding: 0.05 (as a Double, just above
        // the half) reads 0.1; just below reads 0.0 and is left out.
        XCTAssertEqual(value.gMeterValueText(GForce(longitudinal: 0.05, lateral: 0)), "0.1")
        XCTAssertEqual(value.gMeterAccessibilityText(GForce(longitudinal: 0.05, lateral: 0)), "G-meter, 0.1 g accelerating")
        XCTAssertEqual(value.gMeterValueText(GForce(longitudinal: 0.049, lateral: 0)), "0.0")
        XCTAssertEqual(value.gMeterAccessibilityText(GForce(longitudinal: 0.049, lateral: 0)), "G-meter, 0.0 g")
    }

    func testGMeterRangeTextNamesTheActiveRingRadius() {
        XCTAssertEqual(DriveReadout.gMeterRangeText(0.5), "±0.5 G")
        XCTAssertEqual(DriveReadout.gMeterRangeText(1.0), "±1.0 G")
    }

    func testGMeterNoDataNeverShowsZero() throws {
        let stalled = DriveReadout(frame: .unknown)
        var layout1 = DemoTelemetry()
        layout1.layoutVersion = LiveSignalFrame.layoutVersion
        let layout1Readout = DriveReadout(
            frame: try LiveSignalFrame(decoding: layout1.encoded, layoutVersion: layout1.layoutVersion)
        )
        let dropout = try readout {
            $0.statuses[19] = .stale
            $0.statuses[20] = .stale
        }

        for value in [stalled, layout1Readout, dropout] {
            XCTAssertNil(value.acceleration)
            XCTAssertEqual(value.gMeterValueText(nil), "—")
            XCTAssertEqual(value.gMeterStatusText, "NO DATA")
            XCTAssertEqual(value.gMeterAccessibilityText(nil), "G-meter, no data")
        }
    }

    func testGMeterNoDataNamesTheMissingAxis() throws {
        let longitudinalMissing = try readout {
            $0.statuses[19] = .noData
            $0.lateralAcceleration = 0.5
        }
        let lateralUnverified = try readout {
            $0.statuses[20] = .unverified
            $0.longitudinalAcceleration = 2
        }

        XCTAssertEqual(longitudinalMissing.gMeterStatusText, "LONG NO DATA")
        XCTAssertEqual(longitudinalMissing.gMeterAccessibilityText(nil), "G-meter, no data, longitudinal no data")
        XCTAssertEqual(lateralUnverified.gMeterStatusText, "LAT UNVERIFIED")
        XCTAssertEqual(lateralUnverified.gMeterAccessibilityText(nil), "G-meter, no data, lateral unverified")
        // Even if a stale smoothed value were passed, a missing axis wins.
        XCTAssertEqual(lateralUnverified.gMeterValueText(GForce(longitudinal: 0.2, lateral: 0)), "—")
    }

    private func signals(_ change: (inout DemoTelemetry) -> Void) throws -> MotorsportSignals {
        var telemetry = DemoTelemetry()
        change(&telemetry)
        let frame = try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: telemetry.layoutVersion)
        return MotorsportSignals(frame: frame, readout: DriveReadout(frame: frame))
    }

    func testSignalsComeFromTypedFrameValues() throws {
        let left = try signals { $0.turnState = .left }
        XCTAssertTrue(left.leftLit)
        XCTAssertFalse(left.rightLit)

        let hazard = try signals { $0.booleans = 1 << 0 }
        XCTAssertTrue(hazard.leftLit)
        XCTAssertTrue(hazard.rightLit)

        let braking = try signals { $0.booleans = 1 << 12 }
        XCTAssertEqual(braking.brakePressed, true)

        let shifting = try signals { $0.selectorPosition = .shifting }
        XCTAssertEqual(shifting.selector, .shifting)
        XCTAssertTrue(shifting.isShifting)
    }

    func testShiftingShowsQuestionMarkInsteadOfShiftWord() throws {
        let value = try readout {
            $0.selectorPosition = .shifting
            $0.actualGear = .shifting
        }
        let frame = try LiveSignalFrame(decoding: {
            var t = DemoTelemetry(); t.selectorPosition = .shifting; t.actualGear = .shifting; return t.encoded
        }(), layoutVersion: DemoTelemetry().layoutVersion)
        XCTAssertTrue(MotorsportSignals(frame: frame, readout: value).isShifting)
        XCTAssertEqual(value.gearDisplayText(shifting: true), "—")
        XCTAssertEqual(value.selectorDisplayText(shifting: true), "?")
        XCTAssertEqual(value.gearDisplayText(shifting: false), value.gearDisplayText)
    }

    func testStaleSignalsNeverLight() throws {
        let stale = try signals {
            $0.turnState = .left
            $0.booleans = 1 << 0 | 1 << 12
            $0.statuses[2] = .stale
            $0.statuses[6] = .stale
            $0.statuses[18] = .stale
            $0.statuses[4] = .stale
        }
        XCTAssertEqual(stale, .off)
        XCTAssertEqual(MotorsportSignals(frame: .unknown, readout: DriveReadout(frame: .unknown)), .off)
    }

    func testLinkTextUsesLinkState() throws {
        let config = ConfigSummary(try ControllerConfig(canonicalJSON: DemoController.factoryDocument), profile: .preset("Track"))
        let value = DriveReadout(
            frame: try LiveSignalFrame(decoding: DemoTelemetry().encoded, layoutVersion: DemoTelemetry().layoutVersion),
            activeConfig: config,
            rpmBand: AppConfig.default.rpmBand,
            linkState: .connected(.init(id: UUID(), name: "Demo Controller", maximumWriteLength: 182)),
            framesPerSecond: 10
        )

        XCTAssertEqual(value.linkDisplayText, "LINKED")
        XCTAssertEqual(value.linkDisplayText(telemetryFailure: "Live signals are not available."), "LINKED · NO LIVE SIGNALS")
        XCTAssertEqual(
            value.linkAccessibilityText(telemetryFailure: "Live signals are not available."),
            "Link, Linked, Live signals are not available."
        )
    }
}
