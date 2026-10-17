import XCTest
import BLETransport
@testable import CompanionProtocol
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
            activeConfig: activeConfig,
            rpmBand: AppConfig.default.rpmBand
        )
        XCTAssertEqual(atBoundary.rpm, 6000)
        XCTAssertEqual(atBoundary.litShiftLights, 14)
        XCTAssertEqual(atBoundary.rpmFraction, 6000 / 7500, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(atBoundary.redlineFraction), 6000 / 7500, accuracy: 0.0001)
        XCTAssertEqual(atBoundary.redlineState, .active)

        let belowBoundary = DriveReadout(
            frame: try frame { $0.engineRPM = 5999 },
            activeConfig: activeConfig,
            rpmBand: AppConfig.default.rpmBand
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

    // MARK: Acceleration conversion and the both-axes-live rule

    private func accelerationFrame(
        longitudinal: SignalReading<Double>,
        lateral: SignalReading<Double>
    ) -> LiveSignalFrame {
        var frame = LiveSignalFrame.unknown
        frame.longitudinalAcceleration = longitudinal
        frame.lateralAcceleration = lateral
        return frame
    }

    private func fresh(_ value: Double) -> SignalReading<Double> {
        SignalReading(availability: .fresh, value: value)
    }

    func testReadoutConvertsMetresPerSecondSquaredToG() throws {
        let readout = DriveReadout(frame: accelerationFrame(longitudinal: fresh(-9.80665), lateral: fresh(4.903325)))

        let acceleration = try XCTUnwrap(readout.acceleration)
        XCTAssertEqual(acceleration.longitudinal, -1.0, accuracy: 0.0001)
        XCTAssertEqual(acceleration.lateral, 0.5, accuracy: 0.0001)
        XCTAssertEqual(GForce.standardGravity, 9.80665)
        XCTAssertEqual(readout.longitudinalAccelerationFreshness, .fresh)
        XCTAssertEqual(readout.lateralAccelerationFreshness, .fresh)
    }

    func testReadoutHasNoAccelerationUnlessBothAxesAreFreshWithValues() {
        let notLive: [SignalReading<Double>] = [
            SignalReading(availability: .fresh, value: nil),
            SignalReading(availability: .freshnessUnverified, value: 1),
            SignalReading(availability: .stale, value: 1),
            SignalReading(availability: .noData, value: nil),
            SignalReading(availability: .unavailable, value: nil),
            SignalReading(availability: .readFailed, value: nil),
            SignalReading(availability: .notSupported, value: nil),
            .unknown,
        ]
        for reading in notLive {
            let lonOnly = DriveReadout(frame: accelerationFrame(longitudinal: fresh(2), lateral: reading))
            XCTAssertNil(lonOnly.acceleration, "lateral \(reading)")
            let latOnly = DriveReadout(frame: accelerationFrame(longitudinal: reading, lateral: fresh(2)))
            XCTAssertNil(latOnly.acceleration, "longitudinal \(reading)")
        }

        let oneStale = DriveReadout(frame: accelerationFrame(
            longitudinal: fresh(2),
            lateral: SignalReading(availability: .stale, value: 1)
        ))
        XCTAssertEqual(oneStale.longitudinalAccelerationFreshness, .fresh)
        XCTAssertEqual(oneStale.lateralAccelerationFreshness, .stale)
    }

    func testReadoutHasNoAccelerationForLayout1OrAStalledStream() throws {
        var telemetry = DemoTelemetry()
        telemetry.layoutVersion = LiveSignalFrame.layoutVersion
        let layout1 = try LiveSignalFrame(decoding: telemetry.encoded)
        XCTAssertNil(DriveReadout(frame: layout1).acceleration)

        let stalled = DriveReadout(frame: .unknown)
        XCTAssertNil(stalled.acceleration)
        XCTAssertEqual(stalled.longitudinalAccelerationFreshness, .unknown)
        XCTAssertEqual(stalled.lateralAccelerationFreshness, .unknown)
    }
}

// Synthetic typed states isolate semantic projection from packet framing.
func projectionSnapshot(_ signals: [ExtensibleSignalState], stalled: Bool = false, sequence: UInt16 = 513) -> ExtensibleSignalSnapshot {
    ExtensibleSignalSnapshot(catalog: nil, sequence: sequence, isTelemetryStarted: true,
        isStalled: stalled, signals: signals)
}

func projectionSignal(_ key: String, _ type: SignalType, unit: String = "none",
                      availability: SignalAvailability = .fresh,
                      value: ExtensibleSignalValue?, choices: [String] = []) -> ExtensibleSignalState {
    ExtensibleSignalState(descriptor: SignalDescriptor(handle: 91, key: key, type: .known(type),
        unit: unit, evidence: "candidate", choices: choices.enumerated().map {
            SignalEnumChoice(handle: UInt16($0.offset + 30), key: $0.element)
        }), reading: SignalReading(availability: availability, value: value))
}

extension DriveReadoutTests {
    func testDriveReadoutProjectsNormalizedAcceleratorAndBrakePressure() throws {
        let snapshot = projectionSnapshot([
            projectionSignal("vehicle.accelerator_pedal_position", .number,
                             availability: .freshnessUnverified, value: .number(0.5)),
            projectionSignal("vehicle.brake_pressure", .number,
                             availability: .freshnessUnverified, value: .number(37.5)),
        ])
        let readout = DriveReadout(frame: .unknown, snapshot: snapshot)

        XCTAssertEqual(readout.throttleFraction, 0.5)
        XCTAssertEqual(readout.throttlePercent, 50)
        XCTAssertEqual(readout.throttle.value, "50%")
        XCTAssertEqual(readout.throttle.freshness, .unverified)
        XCTAssertEqual(readout.brakePressureBar, 37.5)
        guard let brakePressureFraction = readout.brakePressureFraction else {
            return XCTFail("expected a brake pressure fill")
        }
        XCTAssertEqual(brakePressureFraction, 37.5 / 70, accuracy: 0.000001)
        XCTAssertEqual(readout.brakePressure.value, "37.5 bar")
        XCTAssertEqual(readout.brakePressure.freshness, .unverified)

        let freshSnapshot = projectionSnapshot([
            projectionSignal("vehicle.accelerator_pedal_position", .number,
                             availability: .fresh, value: .number(0.25)),
            projectionSignal("vehicle.brake_pressure", .number,
                             availability: .fresh, value: .number(10)),
        ])
        let freshReadout = DriveReadout(frame: .unknown, snapshot: freshSnapshot)
        XCTAssertEqual(freshReadout.throttle.freshness, .fresh)
        XCTAssertEqual(freshReadout.brakePressure.freshness, .fresh)
    }

    func testDriveReadoutClearsStaleAndInvalidSideSignalValues() {
        let snapshot = projectionSnapshot([
            projectionSignal("vehicle.accelerator_pedal_position", .number,
                             availability: .stale, value: .number(0.5)),
            projectionSignal("vehicle.brake_pressure", .number,
                             availability: .fresh, value: .number(.nan)),
        ])
        let readout = DriveReadout(frame: .unknown, snapshot: snapshot)

        XCTAssertNil(readout.throttleFraction)
        XCTAssertNil(readout.throttlePercent)
        XCTAssertEqual(readout.throttle.freshness, .stale)
        XCTAssertNil(readout.brakePressureBar)
        XCTAssertNil(readout.brakePressureFraction)
        XCTAssertEqual(readout.brakePressure.freshness, .unknown)

        let aboveNormalizedRange = projectionSnapshot([
            projectionSignal("vehicle.accelerator_pedal_position", .number, value: .number(1.01)),
        ])
        let invalidReadout = DriveReadout(frame: .unknown, snapshot: aboveNormalizedRange)
        XCTAssertNil(invalidReadout.throttlePercent)
        XCTAssertEqual(invalidReadout.throttle.freshness, .unknown)
    }

    func testNegativeBrakePressureDisplaysZeroWithoutChangingFreshness() {
        for availability in [SignalAvailability.fresh, .freshnessUnverified] {
            for pressure: Float in [-0.01, -1, -100] {
                let snapshot = projectionSnapshot([
                    projectionSignal("vehicle.brake_pressure", .number,
                                     availability: availability, value: .number(pressure)),
                ])
                let readout = DriveReadout(frame: .unknown, snapshot: snapshot)
                XCTAssertEqual(readout.brakePressureBar, 0)
                XCTAssertEqual(readout.brakePressureFraction, 0)
                XCTAssertEqual(readout.brakePressure.value, "0.0 bar")
                XCTAssertEqual(readout.brakePressureFreshness,
                               availability == .fresh ? .fresh : .unverified)
            }
        }
        let stale = projectionSnapshot([
            projectionSignal("vehicle.brake_pressure", .number,
                             availability: .stale, value: .number(-1)),
        ])
        let readout = DriveReadout(frame: .unknown, snapshot: stale)
        XCTAssertNil(readout.brakePressureBar)
        XCTAssertEqual(readout.brakePressureFreshness, .stale)
    }

    func testDriveReadoutMarksStalledExtensibleSideSignalsUnknown() {
        let snapshot = projectionSnapshot([
            projectionSignal("vehicle.accelerator_pedal_position", .number, value: .number(0.5)),
            projectionSignal("vehicle.brake_pressure", .number, value: .number(20)),
        ], stalled: true)
        let readout = DriveReadout(frame: .unknown, snapshot: snapshot)

        XCTAssertNil(readout.throttlePercent)
        XCTAssertEqual(readout.throttle.freshness, .unknown)
        XCTAssertNil(readout.brakePressureBar)
        XCTAssertEqual(readout.brakePressure.freshness, .unknown)
    }

    func testDriveReadoutUsesDefaultBrakePressureScaleForInvalidConfiguration() throws {
        let snapshot = projectionSnapshot([
            projectionSignal("vehicle.brake_pressure", .number, value: .number(35)),
        ])
        for scale in [0, -1, .nan, .infinity] {
            let readout = DriveReadout(frame: .unknown, snapshot: snapshot,
                                       brakePressureBarScale: scale)
            XCTAssertEqual(try XCTUnwrap(readout.brakePressureFraction), 0.5, accuracy: 0.000001)
        }
    }

    func testBrakePressureKeepsActualValueWhenVisualScaleSaturates() throws {
        let snapshot = projectionSnapshot([
            projectionSignal("vehicle.brake_pressure", .number, value: .number(85)),
        ])
        let readout = DriveReadout(frame: .unknown, snapshot: snapshot)

        XCTAssertEqual(readout.brakePressureBar, 85)
        XCTAssertEqual(readout.brakePressure.value, "85.0 bar")
        XCTAssertEqual(try XCTUnwrap(readout.brakePressureFraction), 1)

        let tinyScale = DriveReadout(frame: .unknown, snapshot: snapshot,
                                    brakePressureBarScale: .leastNonzeroMagnitude)
        XCTAssertEqual(tinyScale.brakePressureFraction, 1)

        let customScale = DriveReadout(frame: .unknown, snapshot: snapshot, brakePressureBarScale: 100)
        XCTAssertEqual(try XCTUnwrap(customScale.brakePressureFraction), 0.85, accuracy: 0.000001)
    }

    func testSemanticProjectionKeepsSignedAccelerationAndBothAxesRule() throws {
        let snapshot = projectionSnapshot([
            projectionSignal("vehicle.acceleration.longitudinal", .number, unit: "m/s^2", value: .number(-9.80665)),
            projectionSignal("vehicle.acceleration.lateral", .number, unit: "m/s^2", value: .number(4.903325)),
        ])
        let projected = LiveSignalProjection.frame(from: snapshot)
        let readout = DriveReadout(frame: projected)
        XCTAssertEqual(try XCTUnwrap(readout.acceleration).longitudinal, -1, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(readout.acceleration).lateral, 0.5, accuracy: 0.000001)
        XCTAssertEqual(projected.longitudinalAcceleration.availability, .fresh)
        let missing = LiveSignalProjection.frame(from: projectionSnapshot([snapshot.signals[0]]))
        XCTAssertNil(DriveReadout(frame: missing).acceleration)
    }

    func testSemanticProjectionRejectsUnitsTypesChoicesAndUnfamiliarKeys() {
        let snapshot = projectionSnapshot([
            projectionSignal("vehicle.engine_rpm", .number, unit: "km/h", value: .number(4000)),
            projectionSignal("vehicle.speed_kph", .boolean, value: .boolean(true)),
            projectionSignal("vehicle.turn_state", .enumeration, value: .enumeration(choiceKey: "left"), choices: ["right"]),
            projectionSignal("vendor.future", .number, unit: "rpm", value: .number(5000)),
        ])
        let projected = LiveSignalProjection.frame(from: snapshot)
        XCTAssertEqual(projected.engineRPM, .unknown)
        XCTAssertEqual(projected.speedKPH, .unknown)
        XCTAssertEqual(projected.turnState, .unknown)
        XCTAssertEqual(snapshot.reading(for: "vendor.future")?.value, .number(5000))
    }

    func testSemanticProjectionPreservesAvailabilityWithoutArrivalFreshness() {
        for availability in [SignalAvailability.noData, .freshnessUnverified, .stale, .unavailable,
                             .readFailed, .notSupported, .unknown] {
            let projected = LiveSignalProjection.frame(from: projectionSnapshot([
                projectionSignal("vehicle.engine_rpm", .number, unit: "rpm", availability: availability, value: .number(4000)),
                projectionSignal("vehicle.brake_pressed", .boolean, availability: availability, value: .boolean(true)),
            ]))
            XCTAssertEqual(projected.engineRPM.availability, availability)
            XCTAssertEqual(projected.brakePressed.availability, availability)
        }
        let brake = LiveSignalProjection.frame(from: projectionSnapshot([
            projectionSignal("vehicle.brake_pressed", .boolean, value: .boolean(true)),
        ]))
        XCTAssertEqual(brake.brakePressed.availability, .freshnessUnverified)
        XCTAssertEqual(DriveReadout(frame: brake).brake.freshness, .unverified)
        let absentValue = LiveSignalProjection.frame(from: projectionSnapshot([
            projectionSignal("vehicle.engine_rpm", .number, unit: "rpm", availability: .noData, value: nil),
        ]))
        XCTAssertEqual(absentValue.engineRPM, SignalReading(availability: .noData, value: nil))
        XCTAssertEqual(LiveSignalProjection.frame(from: projectionSnapshot([], stalled: true)), .unknown)
    }
}
