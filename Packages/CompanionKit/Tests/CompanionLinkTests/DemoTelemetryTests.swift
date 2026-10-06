import XCTest
import os
import BLETransport
import CompanionProtocol
@testable import CompanionLink

/// The demo's frames must be real protocol frames: everything here decodes
/// them with the production decoder rather than reading `DemoTelemetry` fields.
@MainActor
final class DemoTelemetryTests: XCTestCase {
    func testDefaultFrameIsLayout2AndDecodesWithTheRealDecoder() throws {
        var telemetry = DemoTelemetry()
        telemetry.longitudinalAcceleration = 2.5
        telemetry.lateralAcceleration = -0.4
        telemetry.engineRPM = 3000

        XCTAssertEqual(telemetry.layoutVersion, LiveSignalFrame.layout2Version)
        XCTAssertEqual(telemetry.encoded.count, LiveSignalFrame.layout2Length)
        let frame = try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: 2)
        XCTAssertEqual(frame.longitudinalAcceleration, SignalReading(availability: .fresh, value: 2.5))
        XCTAssertEqual(frame.lateralAcceleration, SignalReading(availability: .fresh, value: -0.4))
        XCTAssertEqual(frame.engineRPM, SignalReading(availability: .freshnessUnverified, value: 3000))
        XCTAssertThrowsError(try LiveSignalFrame(decoding: telemetry.encoded), "Layout 2 never decodes as layout 1")
    }

    func testAccelerationStatusesFollowTheirNibbles() throws {
        var telemetry = DemoTelemetry()
        telemetry.longitudinalAcceleration = -7.5
        telemetry.statuses[19] = .unverified
        telemetry.statuses[20] = .noData
        let frame = try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: 2)
        XCTAssertEqual(frame.longitudinalAcceleration, SignalReading(availability: .freshnessUnverified, value: -7.5))
        XCTAssertEqual(frame.lateralAcceleration, SignalReading(availability: .noData, value: nil))
    }

    func testAccelerationBeyondTheWireRangeClamps() throws {
        var telemetry = DemoTelemetry()
        telemetry.lateralAcceleration = 100
        telemetry.longitudinalAcceleration = -1000
        let frame = try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: 2)
        XCTAssertEqual(frame.lateralAcceleration.value, 32.767)
        XCTAssertEqual(frame.longitudinalAcceleration.value, -327.68)
    }

    func testLayout1FrameStillDecodes() throws {
        var telemetry = DemoTelemetry()
        telemetry.layoutVersion = LiveSignalFrame.layoutVersion
        telemetry.engineRPM = 4200
        telemetry.longitudinalAcceleration = 3

        XCTAssertEqual(telemetry.encoded.count, LiveSignalFrame.length)
        let frame = try LiveSignalFrame(decoding: telemetry.encoded)
        XCTAssertEqual(frame.engineRPM.value, 4200)
        XCTAssertEqual(frame.brakePressed.availability, .freshnessUnverified)
        XCTAssertEqual(frame.longitudinalAcceleration, .unknown)
        XCTAssertEqual(frame.lateralAcceleration, .unknown)
        XCTAssertThrowsError(try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: 2))
    }

    func testDemoControllerReportsLayout2InDeviceInfo() throws {
        let demo = DemoController()
        let bytes = try demo.read(CompanionGATT.deviceInfo).get()
        XCTAssertEqual(try DeviceInfo(decoding: bytes).liveSignalLayoutVersion, 2)
    }

    /// One lap sampled at the stream's 10 Hz, decoded as the app decodes it.
    private func driveLap() throws -> [LiveSignalFrame] {
        let samples = Int(DemoTelemetry.driveLapDuration * 10)
        return try (0..<samples).map { index in
            let telemetry = DemoTelemetry.driveLaps(at: Double(index) / 10, sequence: UInt8(truncatingIfNeeded: index))
            XCTAssertEqual(telemetry.encoded.count, LiveSignalFrame.layout2Length)
            return try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: 2)
        }
    }

    /// The frames of one documented phase (preview-scenarios.md, "driveLaps"),
    /// by 10 Hz frame index, so a reordered or shifted timeline fails.
    private func phase(_ frames: [LiveSignalFrame], _ start: Double, _ end: Double) -> ArraySlice<LiveSignalFrame> {
        frames[Int(start * 10)..<Int(end * 10)]
    }

    func testDriveLapsCoversLaunchBrakingAndBothCorners() throws {
        let frames = try driveLap()
        XCTAssertEqual(frames.count, 240)
        func lon(_ frame: LiveSignalFrame) -> Double { frame.longitudinalAcceleration.value ?? .nan }
        func lat(_ frame: LiveSignalFrame) -> Double { frame.lateralAcceleration.value ?? .nan }
        func bothLive(_ frame: LiveSignalFrame) -> Bool {
            frame.longitudinalAcceleration.isLive && frame.lateralAcceleration.isLive
        }

        let launch = phase(frames, 0, 4)
        XCTAssertTrue(launch.allSatisfy(bothLive), "launch: both live")
        XCTAssertTrue(launch.allSatisfy { (2.5...4.5).contains(lon($0)) && abs(lat($0)) <= 0.2 }, "launch: +4.5 easing to +2.5, lateral about 0")
        XCTAssertEqual(lon(launch.first!), 4.5, accuracy: 0.01)
        XCTAssertTrue(launch.allSatisfy { $0.brakePressed.value == false }, "launch: brake off")

        let braking = phase(frames, 4, 6.5)
        XCTAssertTrue(braking.allSatisfy(bothLive), "braking: both live")
        XCTAssertTrue(braking.allSatisfy { (-7.5 ... -5).contains(lon($0)) && lat($0) == 0 }, "braking: −7.5 easing to −5")
        XCTAssertEqual(lon(braking.first!), -7.5, accuracy: 0.01)
        XCTAssertTrue(braking.allSatisfy { $0.brakePressed.value == true }, "braking: brake on")

        // Positive lateral is a right turn; the left-hander comes first.
        let left = phase(frames, 6.5, 10.5)
        XCTAssertTrue(left.allSatisfy(bothLive), "left corner: both live")
        XCTAssertTrue(left.allSatisfy { lat($0) <= 0 && (-0.5...1.5).contains(lon($0)) }, "left corner never leans right")
        XCTAssertLessThan(left.map(lat).min()!, -6.4, "left corner: peak −6.5")
        XCTAssertTrue(left.allSatisfy { $0.brakePressed.value == false }, "left corner: brake off")

        let right = phase(frames, 11.5, 15.5)
        XCTAssertTrue(right.allSatisfy(bothLive), "right corner: both live")
        XCTAssertTrue(right.allSatisfy { lat($0) >= 0 && lon($0) == 1 }, "right corner never leans left")
        XCTAssertGreaterThan(right.map(lat).max()!, 5.9, "right corner: peak +6")

        let stop = phase(frames, 19.5, 24)
        XCTAssertTrue(stop.allSatisfy(bothLive), "stop: both live")
        XCTAssertTrue(stop.allSatisfy { [-3, 0].contains(lon($0)) && lat($0) == 0 }, "stop: −3 then 0")
        XCTAssertEqual(lon(stop.first!), -3)
        XCTAssertEqual(lon(stop.last!), 0)
        XCTAssertTrue(stop.allSatisfy { $0.brakePressed.value == true }, "stop: brake on")
    }

    func testDriveLapsIncludesNonFreshAcceleration() throws {
        let frames = try driveLap()

        let dropout = phase(frames, 10.5, 11.5)
        XCTAssertTrue(dropout.allSatisfy {
            $0.longitudinalAcceleration == SignalReading(availability: .stale, value: nil)
                && $0.lateralAcceleration == SignalReading(availability: .stale, value: nil)
        }, "dropout: both stale without a value")

        let unverified = phase(frames, 15.5, 17.5)
        XCTAssertTrue(unverified.allSatisfy {
            $0.longitudinalAcceleration == SignalReading(availability: .fresh, value: 2)
                && $0.lateralAcceleration == SignalReading(availability: .freshnessUnverified, value: -0.8)
        }, "lateral present but unverified; only longitudinal live")

        let missing = phase(frames, 17.5, 19.5)
        XCTAssertTrue(missing.allSatisfy {
            $0.longitudinalAcceleration == SignalReading(availability: .noData, value: nil)
                && $0.lateralAcceleration == SignalReading(availability: .fresh, value: 0.5)
        }, "longitudinal no data; only lateral live")

        // Outside those windows both axes are live.
        let nonFresh = Set(105..<115).union(155..<195)
        for (index, frame) in frames.enumerated() where !nonFresh.contains(index) {
            XCTAssertTrue(frame.longitudinalAcceleration.isLive && frame.lateralAcceleration.isLive, "frame \(index) live")
        }
    }

    func testNonFiniteAndOutOfRangeValuesEncodeSafely() throws {
        var telemetry = DemoTelemetry()
        telemetry.longitudinalAcceleration = .nan
        telemetry.lateralAcceleration = .infinity
        telemetry.engineRPM = -.infinity
        telemetry.speedKPH = 1e12
        let frame = try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: 2)
        XCTAssertEqual(frame.longitudinalAcceleration.value, 0, "NaN encodes as 0")
        XCTAssertEqual(frame.lateralAcceleration.value, 32.767, "+inf saturates")
        XCTAssertEqual(frame.engineRPM.value, 0, "−inf saturates at the unsigned floor")
        XCTAssertEqual(frame.speedKPH.value, 655.35, "too large saturates")

        telemetry.lateralAcceleration = -.infinity
        telemetry.engineRPM = .nan
        let next = try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: 2)
        XCTAssertEqual(next.lateralAcceleration.value, -32.768)
        XCTAssertEqual(next.engineRPM.value, 0)
    }

    func testDriveLapsLoops() {
        let first = DemoTelemetry.driveLaps(at: 1.3, sequence: 7)
        let next = DemoTelemetry.driveLaps(at: 1.3 + DemoTelemetry.driveLapDuration, sequence: 7)
        XCTAssertEqual(first.encoded, next.encoded)
    }

    // MARK: Scenarios through the real session

    private func liveFrame(
        _ scenario: DemoScenario,
        until condition: (LiveSignalFrame) -> Bool
    ) async throws -> (ControllerSession, LiveSignalFrame) {
        let session = scenario.makeSession(latency: 0.001)
        for _ in 0..<500 where session.phase != .ready {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(session.phase, .ready, "\(scenario)")
        let telemetry = LiveTelemetry(session: session)
        let run = Task { await telemetry.run() }
        defer { run.cancel() }
        for _ in 0..<500 where !condition(telemetry.frame) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertNil(telemetry.failure)
        return (session, telemetry.frame)
    }

    func testDriveLapsScenarioStreamsLayout2ThroughTheSession() async throws {
        let (session, frame) = try await liveFrame(.driveLaps) { $0.longitudinalAcceleration.isLive }
        XCTAssertEqual(session.deviceInfo?.liveSignalLayoutVersion, 2)
        XCTAssertTrue(frame.longitudinalAcceleration.isLive)
        XCTAssertNotNil(frame.engineRPM.value)
    }

    func testDriveLapsLayout1ScenarioStreamsLayout1ThroughTheSession() async throws {
        let (session, frame) = try await liveFrame(.driveLapsLayout1) { $0.engineRPM.value != nil }
        XCTAssertEqual(session.deviceInfo?.liveSignalLayoutVersion, 1)
        // The bytes on the wire, not just what the decoder made of them.
        let lengths = OSAllocatedUnfairLock(initialState: [Int]())
        let subscription = session.client.transport.subscribe(to: .liveSignals) { data in
            lengths.withLock { $0.append(data.count) }
        }
        defer { subscription.cancel() }
        for _ in 0..<500 where lengths.withLock({ $0.count < 3 }) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let received = lengths.withLock { $0 }
        XCTAssertGreaterThanOrEqual(received.count, 3)
        XCTAssertTrue(received.allSatisfy { $0 == LiveSignalFrame.length }, "layout 1 frames are 23 bytes: \(received)")
        XCTAssertNotNil(frame.engineRPM.value)
        XCTAssertEqual(frame.longitudinalAcceleration, .unknown)
        XCTAssertEqual(frame.lateralAcceleration, .unknown)
    }
}
