import Foundation
import EngineSound

/// Applies app preferences through the reusable session contract. Device events
/// and session activation remain owned by the package's session implementation.
final class DriveSoundSession: EngineSoundSession {
    private let lock = NSLock()
    private let base: any EngineSoundSession
    private var policy: AudioSessionMixPolicy
    private var acquiredPolicy: AudioSessionMixPolicy?

    init(base: any EngineSoundSession, policy: AudioSessionMixPolicy) {
        self.base = base
        self.policy = policy
    }

    var isOutputAvailable: Bool { base.isOutputAvailable }
    var thermalState: EngineSoundThermalState { base.thermalState }
    var onEvent: ((EngineSoundSessionEvent) -> Void)? {
        get { base.onEvent }
        set { base.onEvent = newValue }
    }

    func configure(policy: AudioSessionMixPolicy) throws {
        lock.lock()
        defer { lock.unlock() }
        guard self.policy != policy else { return }
        if let previous = acquiredPolicy {
            // Acquire before release: the package's shared coordinator keeps
            // activation while replacing this adapter's policy reference.
            try base.acquire(policy: policy)
            base.release(policy: previous)
            acquiredPolicy = policy
        }
        self.policy = policy
    }

    func acquire(policy: AudioSessionMixPolicy) throws {
        lock.lock()
        defer { lock.unlock() }
        try base.acquire(policy: self.policy)
        acquiredPolicy = self.policy
    }

    func release(policy: AudioSessionMixPolicy) {
        lock.lock()
        defer { lock.unlock() }
        guard let previous = acquiredPolicy else { return }
        base.release(policy: previous)
        acquiredPolicy = nil
    }
}
