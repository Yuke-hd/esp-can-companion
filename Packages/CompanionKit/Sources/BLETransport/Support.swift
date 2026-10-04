import Foundation

// MARK: - Scheduling

/// Cancels work handed to a `BLEScheduler`.
@MainActor
public final class BLECancellable {
    public private(set) var isCancelled = false

    public init() {}

    public func cancel() {
        isCancelled = true
    }
}

/// Runs delayed work on the main actor. Injected so tests can control time.
@MainActor
public protocol BLEScheduler: AnyObject {
    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> BLECancellable
}

/// Real-time scheduler used by the app and previews.
@MainActor
public final class MainActorScheduler: BLEScheduler {
    public init() {}

    @discardableResult
    public func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> BLECancellable {
        let token = BLECancellable()
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !token.isCancelled else { return }
            work()
        }
        return token
    }
}

/// Virtual-time scheduler for tests: nothing runs until the test advances time.
@MainActor
public final class ManualScheduler: BLEScheduler {
    private struct Item {
        let fireAt: TimeInterval
        let sequence: Int
        let token: BLECancellable
        let work: @MainActor () -> Void
    }

    public private(set) var now: TimeInterval = 0
    private var items: [Item] = []
    private var sequence = 0

    public init() {}

    @discardableResult
    public func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> BLECancellable {
        let token = BLECancellable()
        sequence += 1
        items.append(Item(fireAt: now + max(0, delay), sequence: sequence, token: token, work: work))
        return token
    }

    /// Time until the next pending item runs, if any.
    public var nextDelay: TimeInterval? {
        items.filter { !$0.token.isCancelled }.map(\.fireAt).min().map { $0 - now }
    }

    /// Runs everything due within `interval`, including work scheduled along the way.
    public func advance(by interval: TimeInterval) {
        let deadline = now + interval
        while let next = popNext(dueBy: deadline) {
            now = next.fireAt
            next.work()
        }
        now = deadline
    }

    /// Runs the radio's pending responses. The default horizon is short so
    /// reconnect backoff timers stay pending unless a test advances past them.
    public func runUntilIdle(horizon: TimeInterval = 0.5) {
        advance(by: horizon)
    }

    private func popNext(dueBy deadline: TimeInterval) -> Item? {
        items.removeAll { $0.token.isCancelled }
        guard let index = items.indices
            .filter({ items[$0].fireAt <= deadline })
            .min(by: { (items[$0].fireAt, items[$0].sequence) < (items[$1].fireAt, items[$1].sequence) })
        else { return nil }
        return items.remove(at: index)
    }
}

// MARK: - Reconnect policy

/// Backoff for retrying after a failed connection attempt. A dropped link is
/// re-requested immediately instead, because iOS keeps that request pending
/// until the controller is back in range.
public struct ReconnectPolicy: Sendable, Equatable {
    public var initialDelay: TimeInterval
    public var multiplier: Double
    public var maximumDelay: TimeInterval

    public init(initialDelay: TimeInterval = 1, multiplier: Double = 2, maximumDelay: TimeInterval = 30) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maximumDelay = maximumDelay
    }

    /// Delay before retry number `attempt` (starting at 1).
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = Double(max(0, attempt - 1))
        return min(maximumDelay, initialDelay * pow(multiplier, exponent))
    }
}

// MARK: - Remembered device

/// Where the last paired controller is remembered between launches.
@MainActor
public protocol DeviceStore: AnyObject {
    var rememberedDeviceID: PeripheralID? { get set }
}

@MainActor
public final class UserDefaultsDeviceStore: DeviceStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "BLETransport.rememberedDeviceID") {
        self.defaults = defaults
        self.key = key
    }

    public var rememberedDeviceID: PeripheralID? {
        get { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: key) }
    }
}

@MainActor
public final class InMemoryDeviceStore: DeviceStore {
    public var rememberedDeviceID: PeripheralID?

    public init(rememberedDeviceID: PeripheralID? = nil) {
        self.rememberedDeviceID = rememberedDeviceID
    }
}
