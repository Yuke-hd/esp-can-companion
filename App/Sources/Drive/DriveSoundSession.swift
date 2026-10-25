import Foundation
import EngineSound

/// Applies app preferences through the reusable session contract. Device events
/// and session activation remain owned by the package's session implementation.
final class DriveSoundSession: EngineSoundSession {
    // Base acquire/release may synchronously publish a session event.
    private let lock = NSRecursiveLock()
    private let base: any EngineSoundSession
    private var policy: AudioSessionMixPolicy
    private var acquiredPolicy: AudioSessionMixPolicy?
    private var isAppActive = true
    private var outputAvailable: Bool
    private var eventHandler: ((EngineSoundSessionEvent) -> Void)?

    init(base: any EngineSoundSession, policy: AudioSessionMixPolicy) {
        self.base = base
        self.policy = policy
        outputAvailable = base.isOutputAvailable
        base.onEvent = { [weak self] in self?.receive($0) }
    }

    var isOutputAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAppActive && outputAvailable
    }
    var thermalState: EngineSoundThermalState { base.thermalState }
    var onEvent: ((EngineSoundSessionEvent) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return eventHandler
        }
        set {
            lock.lock()
            eventHandler = newValue
            lock.unlock()
        }
    }

    func setAppActive(_ active: Bool) {
        lock.lock()
        guard isAppActive != active else { lock.unlock(); return }
        isAppActive = active
        let handler = eventHandler
        let available = active && outputAvailable
        lock.unlock()
        handler?(.outputRouteChanged(reason: .other, isAvailable: available))
    }

    private func receive(_ event: EngineSoundSessionEvent) {
        lock.lock()
        let handler = eventHandler
        let forwarded: EngineSoundSessionEvent
        if case .outputRouteChanged(let reason, let available) = event {
            outputAvailable = available
            forwarded = .outputRouteChanged(reason: reason, isAvailable: available && isAppActive)
        } else {
            forwarded = event
        }
        lock.unlock()
        handler?(forwarded)
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
