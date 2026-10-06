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
        XCTAssertEqual(value.boostDisplayText, "PLACEHOLDER")
        XCTAssertEqual(value.throttleAccessibilityText, "Throttle, Not supported")
        XCTAssertEqual(value.boostAccessibilityText, "Turbo, placeholder, Not supported")

        let stalled = DriveReadout(frame: .unknown)
        XCTAssertEqual(stalled.throttleDisplayText, "UNKNOWN")
        XCTAssertEqual(stalled.boostDisplayText, "UNKNOWN")
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
