import XCTest
import CompanionProtocol
@testable import CompanionLink

final class PitWallReadoutTests: XCTestCase {
    private func frame(_ change: (inout DemoTelemetry) -> Void = { _ in }) throws -> LiveSignalFrame {
        var telemetry = DemoTelemetry()
        change(&telemetry)
        return try LiveSignalFrame(decoding: telemetry.encoded)
    }

    private let factoryBand = ConfigSummary.RPMBand(fill: .init(from: 0, to: 6500), redline: 6000)

    func testDemoFrameDecodes() throws {
        let decoded = try frame {
            $0.sequence = 7
            $0.engineRPM = 4820
            $0.speedKPH = 72.4
            $0.actualGear = .fourth
            $0.turnState = .left
        }
        XCTAssertEqual(decoded.sequence, 7)
        XCTAssertTrue(decoded.isTelemetryStarted)
        // As on the car, RPM has no freshness timeout; turn state does.
        XCTAssertEqual(decoded.engineRPM, SignalReading(availability: .freshnessUnverified, value: 4820))
        XCTAssertEqual(decoded.turnState.availability, .fresh)
        XCTAssertEqual(decoded.speedKPH.value, 72.4)
        XCTAssertEqual(decoded.actualGear.value, .known(.fourth))
        XCTAssertEqual(decoded.turnState.value, .known(.left))
        XCTAssertEqual(decoded.brakePressed.availability, .freshnessUnverified)
        XCTAssertEqual(decoded.frontWiperPosition, SignalReading(availability: .stale, value: nil))
    }

    func testLiveValues() throws {
        let readout = PitWallReadout(frame: try frame {
            $0.engineRPM = 4820
            $0.speedKPH = 71.6
            $0.actualGear = .fourth
        }, band: factoryBand)

        XCTAssertEqual(readout.rpm, 4820)
        XCTAssertEqual(readout.rpmFreshness, .unverified)
        XCTAssertEqual(readout.gear, "4")
        XCTAssertEqual(readout.speedKPH, 72)
        XCTAssertEqual(readout.isTelemetryStarted, true)
        // 4820 / 6500 of 15 lights.
        XCTAssertEqual(readout.litShiftLights, 11)
        // Lights whose span ends past 6000 rpm: 13 and 14.
        XCTAssertEqual(readout.firstRedShiftLight, 13)
        // Scale is 6500 × 1.08 rounded up to 7500.
        XCTAssertEqual(readout.rpmFraction, 4820 / 7500, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(readout.redlineFraction), 6000 / 7500, accuracy: 0.0001)
    }

    func testUnverifiedRPMIsShownAndLabelled() throws {
        let readout = PitWallReadout(frame: try frame {
            $0.engineRPM = 3000
            $0.statuses[0] = .unverified
        })
        XCTAssertEqual(readout.rpm, 3000)
        XCTAssertEqual(readout.rpmFreshness, .unverified)
    }

    func testStaleValuesAreNotShown() throws {
        let readout = PitWallReadout(frame: try frame {
            $0.statuses[0] = .stale
            $0.statuses[1] = .noData
            $0.statuses[4] = .stale
        })
        XCTAssertNil(readout.rpm)
        XCTAssertEqual(readout.rpmFreshness, .stale)
        XCTAssertNil(readout.speedKPH)
        XCTAssertEqual(readout.speedFreshness, .noData)
        XCTAssertNil(readout.gear)
        XCTAssertEqual(readout.litShiftLights, 0)
        XCTAssertEqual(readout.rpmFraction, 0)
    }

    func testStalledStreamShowsEverythingUnknown() {
        let readout = PitWallReadout(frame: .unknown, band: factoryBand)
        XCTAssertNil(readout.rpm)
        XCTAssertNil(readout.gear)
        XCTAssertNil(readout.speedKPH)
        XCTAssertNil(readout.isTelemetryStarted)
        XCTAssertEqual(readout.litShiftLights, 0)
        for tile in readout.tiles {
            XCTAssertNil(tile.value, tile.title)
            XCTAssertEqual(tile.freshness, .unknown, tile.title)
        }
    }

    func testBrakeIsNeverFresh() throws {
        // A frame that claims a fresh brake is decoded as unknown.
        let claimed = PitWallReadout(frame: try frame {
            $0.booleans = 1 << 12
            $0.statuses[18] = .fresh
        })
        let brake = try XCTUnwrap(claimed.tiles.first { $0.title == "Brake" })
        XCTAssertNil(brake.value)
        XCTAssertEqual(brake.freshness, .unknown)

        let unverified = PitWallReadout(frame: try frame { $0.booleans = 1 << 12 })
        let pressed = try XCTUnwrap(unverified.tiles.first { $0.title == "Brake" })
        XCTAssertEqual(pressed.value, "Pressed")
        XCTAssertEqual(pressed.tone, .active)
        XCTAssertEqual(pressed.freshness, .unverified)
    }

    func testTiles() throws {
        let readout = PitWallReadout(frame: try frame {
            $0.turnState = .left
        })
        let tiles = Dictionary(uniqueKeysWithValues: readout.tiles.map { ($0.title, $0) })
        XCTAssertEqual(readout.tiles.map(\.title), ["Brake", "Turn", "Hazard", "Doors", "Lock", "Wipers"])
        XCTAssertEqual(tiles["Brake"]?.value, "Released")
        XCTAssertEqual(tiles["Turn"]?.value, "Left")
        XCTAssertEqual(tiles["Turn"]?.tone, .active)
        XCTAssertEqual(tiles["Hazard"]?.value, "Off")
        XCTAssertEqual(tiles["Doors"]?.value, "Closed")
        XCTAssertEqual(tiles["Doors"]?.tone, .calm)
        XCTAssertEqual(tiles["Lock"]?.value, "Locked")
        XCTAssertNil(tiles["Wipers"]?.value)
        XCTAssertEqual(tiles["Wipers"]?.freshness, .stale)
        XCTAssertEqual(tiles["Turn"]?.accessibilityText, "Turn, Left, Fresh")
    }

    func testAnyOpenDoorShowsOpen() throws {
        let readout = PitWallReadout(frame: try frame {
            $0.booleans = 1 << 5 // liftgate
            $0.statuses[12] = .stale
        })
        let doors = try XCTUnwrap(readout.tiles.first { $0.title == "Doors" })
        XCTAssertEqual(doors.value, "Open")
        XCTAssertEqual(doors.tone, .active)
    }

    func testDoorsWithAStaleDoorAreNotClosed() throws {
        let readout = PitWallReadout(frame: try frame { $0.statuses[13] = .stale })
        let doors = try XCTUnwrap(readout.tiles.first { $0.title == "Doors" })
        XCTAssertNil(doors.value)
        XCTAssertEqual(doors.freshness, .stale)
    }

    func testGearText() {
        XCTAssertEqual(PitWallReadout.gearText(.known(.reverse)), "R")
        XCTAssertEqual(PitWallReadout.gearText(.known(.parkOrNeutral)), "P/N")
        XCTAssertEqual(PitWallReadout.gearText(.known(.sixth)), "6")
        XCTAssertEqual(PitWallReadout.gearText(.known(.shifting)), "Shift")
        XCTAssertEqual(PitWallReadout.gearText(.known(.unknown)), "?")
        XCTAssertEqual(PitWallReadout.gearText(.unknown(42)), "?")
    }

    func testReportedUnknownChoiceIsAValue() throws {
        let readout = PitWallReadout(frame: try frame {
            $0.turnState = .unknown
            $0.actualGear = .unknown
        })
        let turn = try XCTUnwrap(readout.tiles.first { $0.title == "Turn" })
        XCTAssertEqual(turn.value, "Unknown")
        XCTAssertEqual(turn.tone, .muted)
        XCTAssertEqual(turn.freshness, .fresh)
        XCTAssertEqual(readout.gear, "?")
    }

    func testRedlineWithoutFillRangeStillTurnsLightsRed() throws {
        let band = ConfigSummary.RPMBand(fill: nil, redline: 5800)
        let readout = PitWallReadout(frame: try frame { $0.engineRPM = 6000 }, band: band)
        // Scale is 5800 × 1.08 rounded up to 6500; the row spans 0–6500.
        XCTAssertEqual(readout.firstRedShiftLight, 13)
        XCTAssertEqual(readout.litShiftLights, 14)
    }

    func testNoRPMRulesUsesDefaultScale() throws {
        let readout = PitWallReadout(frame: try frame { $0.engineRPM = 3500 })
        XCTAssertNil(readout.firstRedShiftLight)
        XCTAssertNil(readout.redlineFraction)
        XCTAssertEqual(readout.rpmFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(readout.litShiftLights, 8)
    }

    func testHugeThresholdsDoNotCrash() throws {
        // The controller accepts any finite operand, so a config can carry a
        // threshold far beyond Int's range.
        let config = ControllerConfig(
            actions: [.init(name: "rpm_fill"), .init(name: "red_zone")],
            rules: [
                .range(.init(action: "rpm_fill", signalKey: "vehicle.engine_rpm", input: .init(from: 0, to: 6500), output: .init(from: 0, to: 1))),
                .sampledState(.init(action: "red_zone", signalKey: "vehicle.engine_rpm", comparison: .greater, operand: .number(1e30))),
            ]
        )
        let decoded = try ControllerConfig(canonicalJSON: config.encodedJSON())
        let band = ConfigSummary(decoded).rpmBand
        XCTAssertEqual(band.redline, 1e30)

        let stalled = PitWallReadout(frame: .unknown, band: band)
        XCTAssertNil(stalled.firstRedShiftLight)
        XCTAssertEqual(stalled.litShiftLights, 0)

        let live = PitWallReadout(frame: try frame { $0.engineRPM = 4000 }, band: band)
        XCTAssertNil(live.firstRedShiftLight)
        XCTAssertEqual(live.litShiftLights, 9)
        XCTAssertGreaterThanOrEqual(live.rpmFraction, 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(live.redlineFraction), 1)
    }

    func testExtremeBandsStayInRange() throws {
        let bands: [ConfigSummary.RPMBand] = [
            .init(fill: .init(from: 0, to: 1e30), redline: 6000),
            .init(fill: .init(from: -1e30, to: 1e30), redline: -1e30),
            .init(fill: .init(from: 1e30, to: 1e30), redline: 1e30),
            .init(fill: nil, redline: .greatestFiniteMagnitude),
            .init(fill: .init(from: -.greatestFiniteMagnitude, to: .greatestFiniteMagnitude), redline: .greatestFiniteMagnitude),
        ]
        for band in bands {
            for rpm in [0.0, 4000, 8500] {
                let readout = PitWallReadout(frame: try frame { $0.engineRPM = rpm }, band: band)
                XCTAssertTrue((0...PitWallReadout.shiftLightCount).contains(readout.litShiftLights), "\(band)")
                if let red = readout.firstRedShiftLight {
                    XCTAssertTrue((0..<PitWallReadout.shiftLightCount).contains(red), "\(band)")
                }
                XCTAssertTrue((0...1).contains(readout.rpmFraction), "\(band)")
                if let redline = readout.redlineFraction {
                    XCTAssertTrue((0...1).contains(redline), "\(band)")
                }
            }
        }
    }
}
