import XCTest
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

    func testDriveLapsCoversLaunchBrakingAndBothCorners() throws {
        let frames = try driveLap()
        func live(_ frame: LiveSignalFrame) -> (lon: Double, lat: Double)? {
            guard frame.longitudinalAcceleration.isLive, frame.lateralAcceleration.isLive,
                  let lon = frame.longitudinalAcceleration.value, let lat = frame.lateralAcceleration.value else { return nil }
            return (lon, lat)
        }
        let both = frames.compactMap(live)
        XCTAssertTrue(both.contains { $0.lon > 3 }, "launch")
        XCTAssertTrue(both.contains { $0.lon < -6 }, "braking")
        // Positive lateral is a right turn; the left-hander (6.5–10.5 s) comes first.
        let leftCorner = frames[65..<105].compactMap(live)
        let rightCorner = frames[115..<155].compactMap(live)
        XCTAssertTrue(leftCorner.contains { $0.lat < -4 }, "left corner: negative lateral")
        XCTAssertFalse(leftCorner.contains { $0.lat > 1 }, "left corner never leans right")
        XCTAssertTrue(rightCorner.contains { $0.lat > 4 }, "right corner: positive lateral")
        XCTAssertFalse(rightCorner.contains { $0.lat < -1 }, "right corner never leans left")
        XCTAssertTrue(frames.contains { $0.brakePressed.value == true }, "brake lamp while braking")
    }

    func testDriveLapsIncludesNonFreshAcceleration() throws {
        let frames = try driveLap()
        let lon = frames.map(\.longitudinalAcceleration)
        let lat = frames.map(\.lateralAcceleration)
        XCTAssertTrue(zip(lon, lat).contains { !$0.isLive && !$1.isLive }, "both axes out")
        XCTAssertTrue(zip(lon, lat).contains { $0.isLive && !$1.isLive }, "only longitudinal live")
        XCTAssertTrue(zip(lon, lat).contains { !$0.isLive && $1.isLive }, "only lateral live")
        XCTAssertTrue(lat.contains { $0.availability == .freshnessUnverified && $0.value != nil },
                      "a value present but not fresh")
        XCTAssertTrue(lon.contains { $0.availability == .stale && $0.value == nil }, "stale without a value")
        XCTAssertGreaterThan(zip(lon, lat).filter { $0.isLive && $1.isLive }.count, frames.count / 2,
                             "mostly live, so the meter has something to show")
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
        XCTAssertNotNil(frame.engineRPM.value)
        XCTAssertEqual(frame.longitudinalAcceleration, .unknown)
        XCTAssertEqual(frame.lateralAcceleration, .unknown)
    }
}
