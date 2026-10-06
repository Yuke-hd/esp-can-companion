import XCTest
import BLETransport
import CompanionProtocol
import CompanionLink
@testable import CANCompanion

final class MotorsportDriveTextTests: XCTestCase {
    private func readout(_ change: (inout DemoTelemetry) -> Void = { _ in }) throws -> DriveReadout {
        var telemetry = DemoTelemetry()
        change(&telemetry)
        let frame = try LiveSignalFrame(decoding: telemetry.encoded)
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
        XCTAssertEqual(value.throttleAccessibilityText, "Throttle, not available")
        XCTAssertEqual(value.boostAccessibilityText, "Turbo, placeholder, not available")
    }

    func testLinkTextUsesLinkState() throws {
        let config = ConfigSummary(try ControllerConfig(canonicalJSON: DemoController.factoryDocument), profile: .preset("Track"))
        let value = DriveReadout(
            frame: try LiveSignalFrame(decoding: DemoTelemetry().encoded),
            activeConfig: config,
            linkState: .connected(.init(id: UUID(), name: "Demo Controller", maximumWriteLength: 182)),
            framesPerSecond: 10
        )

        XCTAssertEqual(value.linkDisplayText, "LINKED")
    }
}
