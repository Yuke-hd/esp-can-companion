import Foundation
import CompanionLink
import CompanionProtocol
import EngineSound
import EngineSimCore

/// App-owned conversion and assembly; the reusable follower owns interpolation,
/// age expiry and fading. The controller never calls native controls directly.
@MainActor
final class DriveEngineSoundController {
    private(set) var preferences: EngineSoundPreferences
    private let makeSource: () throws -> any EngineSoundSource
    private let makePlayer: () -> any DriveSoundPlaying
    private let clock: () -> TimeInterval
    private let rpmRange: ClosedRange<Double>
    private var player: (any DriveSoundPlaying)?
    private var source: DriveFollowingSource?
    private var observation: Observation?

    init(
        enabled: Bool = false,
        rpmRange: ClosedRange<Double> = engine_sim_profile_min_rpm(ENGINE_SIM_PROFILE_LS_V8)...engine_sim_profile_max_rpm(ENGINE_SIM_PROFILE_LS_V8),
        makeSource: @escaping () throws -> any EngineSoundSource = { try EngineSimSource() },
        makePlayer: @escaping () -> any DriveSoundPlaying = { EngineSoundPlayer() },
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        preferences = EngineSoundPreferences(isEnabled: enabled)
        self.rpmRange = rpmRange
        self.makeSource = makeSource
        self.makePlayer = makePlayer
        self.clock = clock
    }

    func configure(_ preferences: EngineSoundPreferences) throws {
        self.preferences = preferences
        if preferences.isEnabled {
            try start()
        } else {
            stop()
        }
    }

    func start() throws {
        guard preferences.isEnabled, player == nil else { return }
        let following = DriveFollowingSource(source: try makeSource(), rpmRange: rpmRange, clock: clock)
        let playback = makePlayer()
        do {
            try playback.play(following)
        } catch {
            playback.stop()
            throw error
        }
        source = following
        player = playback
    }

    func receive(_ readout: DriveReadout, receivedAt: ContinuousClock.Instant?, now: ContinuousClock.Instant = .now) {
        guard let source else { return }
        let next = Observation(rpm: readout.rpm, freshness: readout.rpmFreshness,
                               throttle: readout.throttleFraction, connected: readout.linkState.isConnected,
                               receivedAt: receivedAt)
        guard next != observation else { return }
        observation = next
        source.receive(Self.input(for: readout, receivedAt: receivedAt, now: now, sampleTime: clock()))
    }

    func stop() {
        // Player stop joins its producer before releasing the source. Keep our
        // source alive until that quiescence boundary has completed.
        player?.stop()
        player = nil
        source = nil
        observation = nil
    }

    private struct Observation: Equatable {
        let rpm: Double?
        let freshness: PitWallReadout.Freshness
        let throttle: Double?
        let connected: Bool
        let receivedAt: ContinuousClock.Instant?
    }

    static func rpmReceiptTime(in snapshot: ExtensibleSignalSnapshot?) -> ContinuousClock.Instant? {
        guard let snapshot, !snapshot.isStalled else { return nil }
        return snapshot.signals.first {
            $0.descriptor.key.utf8.elementsEqual("vehicle.engine_rpm".utf8) &&
            $0.descriptor.type.known == .number && $0.descriptor.unit == "rpm"
        }?.receivedAt
    }

    static func input(
        for readout: DriveReadout,
        receivedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        sampleTime: TimeInterval
    ) -> RPMFollowerInput {
        let age = receivedAt.map { instant -> Double in
            let elapsed = instant.duration(to: now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        }
        let freshness: RPMFreshness
        if !readout.linkState.isConnected {
            freshness = .disconnected
        } else if let age, age >= 0 {
            switch readout.rpmFreshness {
            case .fresh: freshness = .verified
            case .unverified: freshness = .unverified
            default: freshness = .stale
            }
        } else {
            // Missing timing (including unsupported legacy telemetry) cannot
            // turn an old value into a new observation.
            freshness = .stale
        }
        let live = freshness == .verified || freshness == .unverified
        return RPMFollowerInput(
            rpm: live ? readout.rpm : nil, freshness: freshness, age: age,
            acceleratorThrottle: live ? readout.throttleFraction : nil,
            sampleTime: sampleTime
        )
    }
}

/// The player's producer is the only context that touches the follower and
/// native source. Main-actor observations cross through a bounded latest value.
final class DriveFollowingSource: EngineSoundSource {
    let sampleRate: Double
    private let source: any EngineSoundSource
    private var follower: RPMFollower
    private let clock: () -> TimeInterval
    private let lock = NSLock()
    private var pending: RPMFollowerInput?

    init(source: any EngineSoundSource, rpmRange: ClosedRange<Double>, clock: @escaping () -> TimeInterval) {
        self.source = source
        sampleRate = source.sampleRate
        follower = RPMFollower(rpmRange: rpmRange)
        self.clock = clock
    }

    func receive(_ input: RPMFollowerInput) {
        lock.lock()
        pending = input
        lock.unlock()
    }

    func setTargetRPM(_ rpm: Double) { source.setTargetRPM(rpm) }
    func setThrottle(_ throttle: Double) { source.setThrottle(throttle) }
    func setIgnition(_ enabled: Bool) { source.setIgnition(enabled) }

    @discardableResult
    func render(into buffer: UnsafeMutableBufferPointer<Int16>) -> Int {
        lock.lock()
        let input = pending
        pending = nil
        lock.unlock()
        if let input { follower.update(input) }
        let output = follower.output(at: clock())
        source.setTargetRPM(output.targetRPM)
        source.setThrottle(output.throttle)
        source.setIgnition(output.gain > 0)
        let count = source.render(into: buffer)
        for index in 0..<count {
            buffer[index] = Int16(Double(buffer[index]) * output.gain)
        }
        return count
    }
}

@MainActor
protocol DriveSoundPlaying: AnyObject {
    func play(_ source: any EngineSoundSource) throws
    func stop()
}

extension EngineSoundPlayer: DriveSoundPlaying {
    func play(_ source: any EngineSoundSource) throws {
        try start(source, policy: .mixWithOthers)
    }
}
