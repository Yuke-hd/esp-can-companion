import EngineSound
import EngineSimCore

public enum EngineSoundProfile: Sendable {
    case lsV8
}

public enum EngineSimSourceError: Error {
    case creationFailed
}

/// Owns the native simulator and its synthesizer thread. Destroying the source
/// stops and joins that thread. Freshness/fading belongs to the caller/player.
public final class EngineSimSource: EngineSoundSource {
    public let sampleRate = 44100.0
    private let bridge: OpaquePointer

    public init(profile: EngineSoundProfile = .lsV8) throws {
        let nativeProfile: EngineSimProfile
        switch profile {
        case .lsV8: nativeProfile = ENGINE_SIM_PROFILE_LS_V8
        }
        guard let bridge = engine_sim_create(nativeProfile, 0) else {
            throw EngineSimSourceError.creationFailed
        }
        self.bridge = bridge
    }

    deinit { engine_sim_destroy(bridge) }

    public func setTargetRPM(_ rpm: Double) { engine_sim_set_target_rpm(bridge, rpm) }
    public func setThrottle(_ throttle: Double) { engine_sim_set_throttle(bridge, throttle) }
    public func setIgnition(_ enabled: Bool) { engine_sim_set_ignition(bridge, enabled ? 1 : 0) }

    @discardableResult
    public func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int {
        guard !frames.isEmpty else { return 0 }
        return Int(engine_sim_render(bridge, frames.baseAddress, Int32(clamping: frames.count)))
    }
}
