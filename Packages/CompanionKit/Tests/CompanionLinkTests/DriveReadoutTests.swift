import XCTest
import BLETransport
import CompanionProtocol
@testable import CompanionLink

final class DriveReadoutTests: XCTestCase {
    private func frame(_ change: (inout DemoTelemetry) -> Void = { _ in }) throws -> LiveSignalFrame {
        var telemetry = DemoTelemetry()
        change(&telemetry)
        return try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: telemetry.layoutVersion)
    }

    private var activeConfig: ConfigSummary {
        let config = ControllerConfig(
            actions: [
                .init(name: "rpm_fill"),
                .init(name: "red_zone"),
            ],
            rules: [
                .range(.init(
                    action: "rpm_fill",
                    signalKey: "vehicle.engine_rpm",
                    input: .init(from: 0, to: 6500),
                    output: .init(from: 0, to: 1)
                )),
                .state(.init(
                    action: "red_zone",
                    signalKey: "vehicle.engine_rpm",
                    comparison: .greaterOrEqual,
                    operand: .number(6000)
                )),
            ]
        )
        return ConfigSummary(config, profile: .preset("Track"))
    }

    func testGearAndSelectorUseTheirWireTextAndProfileStatus() throws {
        let link = LinkState.connected(.init(id: UUID(), name: "Bench", maximumWriteLength: 61))
        let readout = DriveReadout(
            frame: try frame {
                $0.actualGear = .reverse
                $0.selectorPosition = .drive
            },
            activeConfig: activeConfig,
            linkState: link,
            framesPerSecond: 10
        )

        XCTAssertEqual(readout.gear, "R")
        XCTAssertEqual(readout.gearFreshness, .unverified)
        XCTAssertEqual(readout.selector, "D")
        XCTAssertEqual(readout.selectorFreshness, .unverified)
        XCTAssertEqual(readout.status.linkState, link)
        XCTAssertEqual(readout.status.telemetryStarted, true)
        XCTAssertEqual(readout.status.frameRate, 10)
        XCTAssertEqual(readout.status.profileName, "Track")
    }

    func testRPMScalingAndRedlineUsePitWallBoundary() throws {
        let atBoundary = DriveReadout(
            frame: try frame { $0.engineRPM = 6000 },
            activeConfig: activeConfig
        )
        XCTAssertEqual(atBoundary.rpm, 6000)
        XCTAssertEqual(atBoundary.litShiftLights, 14)
        XCTAssertEqual(atBoundary.rpmFraction, 6000 / 7500, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(atBoundary.redlineFraction), 6000 / 7500, accuracy: 0.0001)
        XCTAssertEqual(atBoundary.redlineState, .active)

        let belowBoundary = DriveReadout(
            frame: try frame { $0.engineRPM = 5999 },
            activeConfig: activeConfig
        )
        XCTAssertEqual(belowBoundary.redlineState, .standby)
    }

    func testRPMNeverReportsFresh() throws {
        let readout = DriveReadout(frame: try frame {
            $0.engineRPM = 4000
            $0.statuses[0] = .fresh
        })

        XCTAssertEqual(readout.rpm, 4000)
        XCTAssertEqual(readout.rpmFreshness, .unverified)
    }

    func testTurnAndHazardMatchPitWallTileMapping() throws {
        let left = DriveReadout(frame: try frame { $0.turnState = .left })
        XCTAssertEqual(left.turn.value, "Left")
        XCTAssertEqual(left.turn.tone, .active)
        XCTAssertEqual(left.hazard.value, "Off")
        XCTAssertEqual(left.hazard.tone, .muted)

        let right = DriveReadout(frame: try frame { $0.turnState = .right })
        XCTAssertEqual(right.turn.value, "Right")

        let hazard = DriveReadout(frame: try frame {
            $0.turnState = .hazard
            $0.booleans |= 1 << 0
        })
        XCTAssertEqual(hazard.turn.value, "Both")
        XCTAssertEqual(hazard.hazard.value, "On")
        XCTAssertEqual(hazard.hazard.tone, .active)
    }

    func testBrakeShowsOnAndOffWithControllerFreshness() throws {
        let pressed = DriveReadout(frame: try frame { $0.booleans |= 1 << 12 })
        XCTAssertEqual(pressed.brake.value, "Pressed")
        XCTAssertEqual(pressed.brake.tone, .active)
        XCTAssertEqual(pressed.brake.freshness, .unverified)

        let released = DriveReadout(frame: try frame())
        XCTAssertEqual(released.brake.value, "Released")
        XCTAssertEqual(released.brake.freshness, .unverified)

        let claimedFresh = DriveReadout(frame: try frame {
            $0.statuses[18] = .fresh
        })
        XCTAssertNil(claimedFresh.brake.value)
        XCTAssertEqual(claimedFresh.brake.freshness, .unknown)
    }

    func testUnsupportedInputsAreExplicitPlaceholders() throws {
        let readout = DriveReadout(frame: try frame())

        for tile in [readout.throttle, readout.brakePressure, readout.boost] {
            XCTAssertNil(tile.value, tile.title)
            XCTAssertEqual(tile.freshness, .unsupported, tile.title)
        }
    }

    func testStalledFrameClearsLiveValuesAndRedline() {
        let readout = DriveReadout(frame: .unknown, activeConfig: activeConfig, framesPerSecond: 10)

        XCTAssertNil(readout.rpm)
        XCTAssertNil(readout.gear)
        XCTAssertNil(readout.selector)
        XCTAssertNil(readout.speedKPH)
        XCTAssertEqual(readout.redlineState, .standby)
        XCTAssertNil(readout.status.telemetryStarted)
        XCTAssertEqual(readout.status.frameRate, 0)
        for tile in [readout.brake, readout.turn, readout.hazard, readout.doors, readout.lock,
                     readout.throttle, readout.brakePressure, readout.boost] {
            XCTAssertNil(tile.value, tile.title)
            XCTAssertEqual(tile.freshness, .unknown, tile.title)
        }
    }
}
