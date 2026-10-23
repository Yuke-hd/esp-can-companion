import XCTest
import BLETransport
import CompanionLink
@testable import CompanionProtocol
import EngineSound
@testable import CANCompanion

@MainActor
final class DriveEngineSoundControllerTests: XCTestCase {
    private let start = ContinuousClock.now

    func testUnverifiedRPMKeepsItsActualReceiptAge() async {
        let value = readout(rpm: 3000, availability: .freshnessUnverified)
        let input = DriveEngineSoundController.input(
            for: value, receivedAt: start, now: start + .milliseconds(250), sampleTime: 10)

        XCTAssertEqual(value.rpmFreshness, .unverified)
        XCTAssertEqual(input.rpm, 3000)
        XCTAssertEqual(input.freshness, .unverified)
        XCTAssertEqual(input.age, 0.25)
        XCTAssertEqual(input.sampleTime, 10)
        XCTAssertEqual(input.acceleratorThrottle, 0.5)
    }

    func testWireFreshRPMRemainsUnverifiedAndUnknownNeverKeepsRPM() async {
        let claimedFresh = readout(rpm: 2000, availability: .fresh)
        let input = DriveEngineSoundController.input(
            for: claimedFresh, receivedAt: start, now: start, sampleTime: 0)
        XCTAssertEqual(input.freshness, .unverified)

        for unavailable in [SignalAvailability.stale, .unknown, .readFailed, .noData, .unavailable, .notSupported] {
            let value = readout(rpm: 2000, availability: unavailable)
            let unknown = DriveEngineSoundController.input(
                for: value, receivedAt: start, now: start, sampleTime: 0)
            XCTAssertNil(unknown.rpm)
            XCTAssertEqual(unknown.freshness, .stale)
        }
    }

    func testDisconnectedOrUntimestampedValuesAreSilentInputs() async {
        let disconnected = DriveEngineSoundController.input(
            for: readout(rpm: 3000, connected: false), receivedAt: start, now: start, sampleTime: 0)
        XCTAssertNil(disconnected.rpm)
        XCTAssertEqual(disconnected.freshness, .disconnected)

        let untimestamped = DriveEngineSoundController.input(
            for: readout(rpm: 3000), receivedAt: nil, now: start, sampleTime: 0)
        XCTAssertNil(untimestamped.rpm)
        XCTAssertEqual(untimestamped.freshness, .stale)
    }

    func testReceiptLookupRequiresCanonicalNumericRPMAndAValidStream() async {
        func state(_ type: SignalType, _ unit: String) -> ExtensibleSignalState {
            .init(descriptor: .init(handle: 9, key: "vehicle.engine_rpm", type: .known(type), unit: unit,
                                   evidence: "test", choices: []),
                  reading: .init(availability: .freshnessUnverified, value: .number(3000)), receivedAt: start)
        }
        func snapshot(_ signals: [ExtensibleSignalState], stalled: Bool = false) -> ExtensibleSignalSnapshot {
            .init(catalog: nil, sequence: 1, isTelemetryStarted: true, isStalled: stalled, signals: signals)
        }
        XCTAssertNil(DriveEngineSoundController.rpmReceiptTime(in: nil))
        XCTAssertNil(DriveEngineSoundController.rpmReceiptTime(in: snapshot([state(.number, "none")])))
        XCTAssertNil(DriveEngineSoundController.rpmReceiptTime(in: snapshot([state(.boolean, "rpm")])))
        XCTAssertNil(DriveEngineSoundController.rpmReceiptTime(in: snapshot([state(.number, "rpm")], stalled: true)))
        XCTAssertEqual(DriveEngineSoundController.rpmReceiptTime(in: snapshot([state(.number, "rpm")])), start)
    }

    func testSoundDefaultsOffAndDisabledControllerDoesNotAllocateAudio() async throws {
        XCTAssertFalse(EngineSoundPreferences().isEnabled)
        XCTAssertTrue(EngineSoundPreferences().lowersOtherAudio)
        let controller = DriveEngineSoundController(makeSource: {
            XCTFail("Disabled sound must not create the native source")
            return ToneSource()
        }, makePlayer: { _ in
            XCTFail("Disabled sound must not create playback")
            return RecordingPlayer()
        })
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        try controller.start()
        controller.stop()
    }

    func testPersistedPreferencesStartStopAndExposeDuckingWithoutRestart() async throws {
        let player = RecordingPlayer()
        let controller = DriveEngineSoundController(makeSource: { ToneSource() }, makePlayer: { _ in player })
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        try controller.configure(.init(isEnabled: false, lowersOtherAudio: true))
        XCTAssertEqual(player.starts, 0)
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: true))
        XCTAssertEqual(player.starts, 1)
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: false))
        XCTAssertEqual(player.starts, 1, "Preference changes must not restart playback")
        XCTAssertFalse(controller.preferences.lowersOtherAudio)
        XCTAssertEqual(player.stops, 0)
        try controller.configure(.init(isEnabled: false, lowersOtherAudio: false))
        XCTAssertEqual(player.stops, 1)
        XCTAssertNil(player.source)
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: false))
        XCTAssertEqual(player.starts, 2)
        controller.stop()
    }

    func testLifecycleRequiresVisibleActiveDriveAndStopsOnExitOrBackground() async throws {
        let player = RecordingPlayer()
        let controller = DriveEngineSoundController(enabled: true, makeSource: { ToneSource() }, makePlayer: { _ in player })
        try controller.start()
        try controller.setLifecycle(isDriveVisible: false, isAppActive: true)
        try controller.setLifecycle(isDriveVisible: true, isAppActive: false)
        XCTAssertEqual(player.starts, 0)
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        XCTAssertEqual(player.starts, 1)
        try controller.setLifecycle(isDriveVisible: true, isAppActive: false)
        XCTAssertEqual(player.stops, 1)
        XCTAssertNil(player.source)
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        XCTAssertEqual(player.starts, 2)
        try controller.setLifecycle(isDriveVisible: false, isAppActive: true)
        XCTAssertEqual(player.stops, 2)
        try controller.setLifecycle(isDriveVisible: false, isAppActive: false)
        try controller.setLifecycle(isDriveVisible: false, isAppActive: true)
        XCTAssertEqual(player.starts, 2)
    }

    func testFailedLivePolicyChangeKeepsPreviousSessionAndCanStillStop() async throws {
        let session = RecordingSession()
        let player = SessionPlayer()
        let controller = DriveEngineSoundController(makeSource: { ToneSource() }, makePlayer: {
            player.session = $0
            return player
        }, makeSession: { session })
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: true))
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        session.failAcquire = true
        XCTAssertThrowsError(try controller.configure(.init(isEnabled: true, lowersOtherAudio: false)))
        XCTAssertTrue(controller.preferences.lowersOtherAudio)
        XCTAssertEqual(player.starts, 1)
        XCTAssertEqual(session.calls, ["acquire:duck", "acquire:mix"])
        // Turning sound off must work even while session acquisition fails.
        try controller.configure(.init(isEnabled: false, lowersOtherAudio: false))
        XCTAssertEqual(session.calls.last, "release:duck")
        XCTAssertEqual(player.stops, 1)
    }

    func testLiveSessionPolicyChangesPreservePlayerAndForwardPackageEvents() async throws {
        let session = RecordingSession()
        let player = SessionPlayer()
        let controller = DriveEngineSoundController(makeSource: { ToneSource() }, makePlayer: {
            player.session = $0
            return player
        }, makeSession: { session })
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: true))
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        XCTAssertEqual(session.calls, ["acquire:duck"])
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: false))
        XCTAssertEqual(session.calls, ["acquire:duck", "acquire:mix", "release:duck"])
        XCTAssertEqual(player.starts, 1)
        XCTAssertEqual(player.stops, 0)
        let events: [EngineSoundSessionEvent] = [.interruptionBegan, .interruptionEnded(shouldResume: false),
            .outputRouteChanged(reason: .oldDeviceUnavailable, isAvailable: true),
            .thermalStateChanged(.critical), .thermalStateChanged(.nominal)]
        events.forEach { session.onEvent?($0) }
        XCTAssertEqual(player.events, events)
        // A preference update while the package is paused must not request start.
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: true))
        XCTAssertEqual(player.starts, 1)
        try controller.configure(.init(isEnabled: false, lowersOtherAudio: true))
        XCTAssertEqual(player.stops, 1)
        session.onEvent?(.interruptionEnded(shouldResume: true))
        session.onEvent?(.thermalStateChanged(.nominal))
        try controller.setLifecycle(isDriveVisible: true, isAppActive: false)
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        XCTAssertEqual(player.starts, 1, "Explicit off survives recovery events and foregrounding")
        XCTAssertEqual(session.calls.last, "release:duck")
    }

    func testScriptedToneTracksRPMAndExpiresWithoutNewObservations() async throws {
        var time = 10.0
        let tone = RecordingTone()
        let player = RecordingPlayer()
        let controller = DriveEngineSoundController(enabled: true, rpmRange: 1000...7000,
            makeSource: { tone }, makePlayer: { _ in player }, clock: { time })
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        try controller.start()
        XCTAssertTrue(player.render().allSatisfy { $0 == 0 })
        controller.receive(readout(rpm: 3000), receivedAt: start, now: start)
        _ = player.render()
        time += 0.11
        XCTAssertTrue(player.render().contains { $0 != 0 })
        XCTAssertEqual(tone.rpm, 3000, accuracy: 0.001)
        XCTAssertEqual(tone.throttle, 0.5)

        time += 0.01
        controller.receive(readout(rpm: 5000), receivedAt: start + .milliseconds(120), now: start + .milliseconds(120))
        _ = player.render()
        time += 0.11
        _ = player.render()
        XCTAssertEqual(tone.rpm, 5000, accuracy: 0.001)
        // A repaint of the same cached RPM does not renew its observation.
        time = 11
        controller.receive(readout(rpm: 5000), receivedAt: start + .milliseconds(120), now: start + .seconds(1))
        XCTAssertTrue(player.render().allSatisfy { $0 == 0 })
        XCTAssertEqual(tone.rpm, 1000)
        controller.stop()
        XCTAssertEqual(player.stops, 1)
        XCTAssertNil(player.source)
    }

    func testUnknownStaleAndDisconnectedFadeToSilenceAndStopReleasesSource() async throws {
        for availability in [SignalAvailability.unknown, .stale, .freshnessUnverified] {
            var time = 0.0
            let player = RecordingPlayer()
            weak var released: RecordingTone?
            let controller = DriveEngineSoundController(enabled: true, rpmRange: 1000...7000, makeSource: {
                let tone = RecordingTone()
                released = tone
                return tone
            }, makePlayer: { _ in player }, clock: { time })
            try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
            try controller.start()
            controller.receive(readout(rpm: 3000), receivedAt: start, now: start)
            _ = player.render()
            time = 0.11
            XCTAssertTrue(player.render().contains { $0 != 0 })
            controller.receive(readout(rpm: 3000, availability: availability,
                                       connected: availability != .freshnessUnverified), receivedAt: nil, now: start)
            _ = player.render()
            XCTAssertEqual(released?.rpm, 1000)
            time = 0.4
            XCTAssertTrue(player.render().allSatisfy { $0 == 0 })
            controller.stop()
            XCTAssertNil(released, "Drive exit must release the native source after playback stops")
            controller.stop()
            XCTAssertEqual(player.stops, 1)
        }
    }

    func testPlaybackFailureReleasesSourceAndCanRetry() async throws {
        let player = RecordingPlayer()
        player.fail = true
        weak var released: RecordingTone?
        let controller = DriveEngineSoundController(enabled: true, makeSource: {
            let tone = RecordingTone()
            released = tone
            return tone
        }, makePlayer: { _ in player })
        XCTAssertThrowsError(try controller.setLifecycle(isDriveVisible: true, isAppActive: true))
        XCTAssertNil(released)
        XCTAssertEqual(player.stops, 1)
        player.fail = false
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        try controller.start()
        XCTAssertNotNil(released)
        controller.stop()
        XCTAssertNil(released)
    }

    #if os(iOS) && targetEnvironment(simulator)
    func testReusablePlayerSessionPauseRecoveryAndOffIntent() async throws {
        let session = RecordingSession()
        var player: EngineSoundPlayer!
        let controller = DriveEngineSoundController(makeSource: { ToneSource() }, makePlayer: {
            player = EngineSoundPlayer(session: $0)
            return player
        }, makeSession: { session })
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: true))
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        defer { controller.stop() }
        XCTAssertTrue(player.isPlaying)
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: false))
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(session.calls, ["acquire:duck", "acquire:mix", "release:duck"])
        session.onEvent?(.interruptionBegan)
        XCTAssertFalse(player.isPlaying)
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: true))
        XCTAssertFalse(player.isPlaying, "Changing policy must respect package interruption pause")
        session.onEvent?(.interruptionEnded(shouldResume: true))
        XCTAssertTrue(player.isPlaying)
        session.onEvent?(.thermalStateChanged(.critical))
        XCTAssertFalse(player.isPlaying)
        session.onEvent?(.thermalStateChanged(.nominal))
        XCTAssertTrue(player.isPlaying)
        session.onEvent?(.outputRouteChanged(reason: .oldDeviceUnavailable, isAvailable: true))
        XCTAssertFalse(player.isPlaying)
        try controller.configure(.init(isEnabled: true, lowersOtherAudio: false))
        XCTAssertFalse(player.isPlaying, "Settings must not override route-removal pause")
        try controller.configure(.init(isEnabled: false, lowersOtherAudio: false))
        session.onEvent?(.interruptionEnded(shouldResume: true))
        session.onEvent?(.thermalStateChanged(.nominal))
        XCTAssertFalse(player.isPlaying)
        try controller.setLifecycle(isDriveVisible: true, isAppActive: false)
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        XCTAssertFalse(player.isPlaying, "Explicit off must survive foregrounding")
    }

    func testSimulatorPlaybackConsumesFramesAndDriveStopReleasesItsSource() async throws {
        let player = EngineSoundPlayer()
        weak var released: RecordingTone?
        let controller = DriveEngineSoundController(enabled: true, makeSource: {
            let tone = RecordingTone()
            released = tone
            return tone
        }, makePlayer: { _ in player })
        try controller.setLifecycle(isDriveVisible: true, isAppActive: true)
        try controller.start()
        defer { controller.stop() }
        controller.receive(readout(rpm: 3000), receivedAt: .now)
        let deadline = ContinuousClock.now + .seconds(10)
        while player.consumedFrameCount == 0 && player.lastPlaybackFailure == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(player.lastPlaybackFailure)
        XCTAssertTrue(player.isPlaying)
        XCTAssertGreaterThan(player.consumedFrameCount, 0, "The Simulator audio callback must consume producer frames")
        controller.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(released, "Stopping Drive must join playback and release its source")
    }
    #endif

    private func readout(rpm: Double, availability: SignalAvailability = .freshnessUnverified,
                         connected: Bool = true) -> DriveReadout {
        var frame = LiveSignalFrame.unknown
        frame.isTelemetryStarted = true
        frame.engineRPM = .init(availability: availability, value: rpm)
        let link: LinkState = connected
            ? .connected(.init(id: UUID(), name: "Test controller", maximumWriteLength: 61)) : .idle
        let accelerator = ExtensibleSignalState(descriptor: SignalDescriptor(handle: 1,
            key: "vehicle.accelerator_pedal_position", type: .known(.number), unit: "none", evidence: "test", choices: []),
            reading: .init(availability: .freshnessUnverified, value: .number(0.5)))
        let snapshot = ExtensibleSignalSnapshot(catalog: nil, sequence: 1, isTelemetryStarted: true,
            isStalled: false, signals: [accelerator])
        return DriveReadout(frame: frame, snapshot: snapshot, linkState: link)
    }
}

@MainActor
private final class RecordingPlayer: DriveSoundPlaying {
    var source: (any EngineSoundSource)?
    var starts = 0
    var stops = 0
    var fail = false
    func play(_ source: any EngineSoundSource) throws {
        self.source = source
        starts += 1
        if fail { throw NSError(domain: "test.playback", code: 1) }
    }
    func stop() { stops += 1; source = nil }
    func render() -> [Int16] {
        var pcm = [Int16](repeating: 0, count: 512)
        _ = pcm.withUnsafeMutableBufferPointer { source?.render(into: $0) }
        return pcm
    }
}

private final class RecordingTone: EngineSoundSource {
    private let tone = ToneSource()
    var sampleRate: Double { tone.sampleRate }
    private(set) var rpm = 0.0
    private(set) var throttle = 0.0
    func setTargetRPM(_ rpm: Double) { self.rpm = rpm; tone.setTargetRPM(rpm) }
    func setThrottle(_ throttle: Double) { self.throttle = throttle; tone.setThrottle(throttle) }
    func setIgnition(_ enabled: Bool) { tone.setIgnition(enabled) }
    func render(into buffer: UnsafeMutableBufferPointer<Int16>) -> Int { tone.render(into: buffer) }
}

private final class RecordingSession: EngineSoundSession {
    var isOutputAvailable = true
    var thermalState: EngineSoundThermalState = .nominal
    var onEvent: ((EngineSoundSessionEvent) -> Void)?
    var calls: [String] = []
    var failAcquire = false
    func acquire(policy: AudioSessionMixPolicy) throws {
        calls.append("acquire:\(policy == .duckOthers ? "duck" : "mix")")
        if failAcquire { throw NSError(domain: "test.session", code: 1) }
    }
    func release(policy: AudioSessionMixPolicy) { calls.append("release:\(policy == .duckOthers ? "duck" : "mix")") }
}

@MainActor
private final class SessionPlayer: DriveSoundPlaying {
    var session: (any EngineSoundSession)?
    var starts = 0
    var stops = 0
    var events: [EngineSoundSessionEvent] = []
    func play(_ source: any EngineSoundSource) throws {
        starts += 1
        session?.onEvent = { [weak self] in self?.events.append($0) }
        try session?.acquire(policy: .mixWithOthers)
    }
    func stop() {
        stops += 1
        session?.release(policy: .mixWithOthers)
        session?.onEvent = nil
    }
}
