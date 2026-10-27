import Foundation
import BLETransport
import CompanionProtocol

/// Runs the protocol client over `ConnectionManager`: implements
/// `CompanionTransport` for whichever controller the manager is connected to.
///
/// Errors map as follows:
/// - not linked: `.notConnected`, the only case where a write surely never
///   left the phone;
/// - an ATT error response: `.att` with the controller's code;
/// - the link dropped before the answer: `.disconnected`;
/// - any other radio error: `.other`. The client treats it like a drop, an
///   unknown outcome, during a commit or command.
/// - a request the manager refused (not an allowed characteristic, payload
///   over the MTU): `.other`. These are programming errors.
public final class ConnectionManagerTransport: CompanionTransport, @unchecked Sendable {
    public let manager: ConnectionManager

    // A departing screen's asynchronous CCCD cleanup must finish before the
    // next screen activates its stream on the same connection.
    @MainActor private var notifierTransition: Task<Void, Never>?

    private let lock = NSLock()
    private var subscribers: [CompanionCharacteristic: [UUID: @Sendable (Data) -> Void]] = [:]

    @MainActor
    public init(manager: ConnectionManager) {
        self.manager = manager
        manager.observeNotifications { [weak self] uuid, value in
            guard let self, let characteristic = Self.characteristic(for: uuid) else { return }
            self.deliver(value, for: characteristic)
        }
    }

    // MARK: CompanionTransport

    public func read(_ characteristic: CompanionCharacteristic) async throws -> Data {
        do {
            return try await manager.read(Self.gattUUID(for: characteristic))
        } catch let error as ConnectionError {
            throw Self.transportError(error)
        }
    }

    public func write(_ value: Data, to characteristic: CompanionCharacteristic) async throws {
        do {
            try await manager.write(value, to: Self.gattUUID(for: characteristic))
        } catch let error as ConnectionError {
            throw Self.transportError(error)
        }
    }

    public func maximumWriteLength() async throws -> Int {
        let state = await manager.state
        guard case .connected(let device) = state else {
            throw CompanionTransportError.notConnected
        }
        return device.maximumWriteLength
    }

    public func availableCharacteristics() async throws -> Set<CompanionCharacteristic> {
        try await discoveredCharacteristics()
    }

    @MainActor
    private func discoveredCharacteristics() throws -> Set<CompanionCharacteristic> {
        guard manager.state.isConnected else { throw CompanionTransportError.notConnected }
        return Set(manager.availableCharacteristics.compactMap(Self.characteristic))
    }

    public func activateLiveNotifier(_ characteristic: CompanionCharacteristic) async throws -> CompanionSubscription {
        try await activateOnManager(characteristic)
    }

    @MainActor
    private func activateOnManager(_ characteristic: CompanionCharacteristic) async throws -> CompanionSubscription {
        let previous = notifierTransition
        let activation = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await self.selectNotifier(characteristic)
        }
        notifierTransition = Task { _ = try? await activation.value }
        return try await withTaskCancellationHandler {
            try await activation.value
        } onCancel: {
            activation.cancel()
        }
    }

    @MainActor
    private func selectNotifier(_ characteristic: CompanionCharacteristic) async throws -> CompanionSubscription {
        guard characteristic == .liveSignals || characteristic == .extensibleLiveSignals else {
            throw CompanionTransportError.other("Characteristic is not a live notifier.")
        }
        do {
            try await manager.selectLiveNotifier(Self.gattUUID(for: characteristic))
            guard let generation = manager.selectedLiveNotifierID else { throw CompanionTransportError.disconnected }
            let lease = NotifierLease {
                Task { @MainActor in self.enqueueNotifierCleanup(selectionID: generation) }
            }
            manager.onLiveNotifierTermination(selectionID: generation) { [weak lease] in lease?.finish() }
            return lease
        } catch let error as LiveNotifierError {
            switch error {
            case .notConnected: throw CompanionTransportError.notConnected
            case .disconnected: throw CompanionTransportError.disconnected
            case .failed(.att(let code)): throw CompanionTransportError.att(ATTError(rawValue: code))
            default: throw CompanionTransportError.other(String(describing: error))
            }
        }
    }

    @MainActor
    private func enqueueNotifierCleanup(selectionID: UUID) {
        let previous = notifierTransition
        notifierTransition = Task { [weak manager] in
            await previous?.value
            try? await manager?.clearLiveNotifier(ifSelectionID: selectionID)
        }
    }

    public func subscribe(
        to characteristic: CompanionCharacteristic,
        handler: @escaping @Sendable (Data) -> Void
    ) -> CompanionSubscription {
        let id = UUID()
        lock.withLock { subscribers[characteristic, default: [:]][id] = handler }
        return Subscription { [weak self] in
            guard let self else { return }
            _ = self.lock.withLock { self.subscribers[characteristic]?.removeValue(forKey: id) }
        }
    }

    // MARK: Mapping

    static func gattUUID(for characteristic: CompanionCharacteristic) -> GATTUUID {
        switch characteristic {
        case .deviceInfo: CompanionGATT.deviceInfo
        case .config: CompanionGATT.config
        case .configStatus: CompanionGATT.configStatus
        case .liveSignals: CompanionGATT.liveSignals
        case .command: CompanionGATT.command
        case .signalCatalog: CompanionGATT.signalCatalog
        case .outputCatalog: CompanionGATT.outputCatalog
        case .extensibleLiveSignals: CompanionGATT.extensibleLiveSignals
        }
    }

    static func characteristic(for uuid: GATTUUID) -> CompanionCharacteristic? {
        CompanionCharacteristic.allCases.first { gattUUID(for: $0) == uuid }
    }

    static func transportError(_ error: ConnectionError) -> CompanionTransportError {
        switch error {
        case .notConnected:
            .notConnected
        case .disconnected:
            .disconnected
        case .writeFailed(.att(let code)), .readFailed(.att(let code)):
            .att(ATTError(rawValue: code))
        case .writeFailed(let radioError), .readFailed(let radioError):
            .other(String(describing: radioError))
        case .characteristicNotWritable, .characteristicNotReadable, .payloadTooLarge:
            // Refused before anything was sent.
            .other(String(describing: error))
        }
    }

    /// Runs on the main actor, synchronously from the manager's notification
    /// event, so handlers see a notification before the response to any write
    /// the controller answered after sending it.
    private func deliver(_ value: Data, for characteristic: CompanionCharacteristic) {
        let handlers = lock.withLock { Array((subscribers[characteristic] ?? [:]).values) }
        for handler in handlers { handler(value) }
    }
}

private struct Subscription: CompanionSubscription {
    let onCancel: @Sendable () -> Void
    func cancel() { onCancel() }
}

/// The lease's terminal state is synchronous so a packet callback can gate
/// delivery immediately even while actor cleanup is waiting to run.
private final class NotifierLease: CompanionSubscription, @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    private var termination: (@Sendable () -> Void)?
    private let cancelSelection: @Sendable () -> Void

    init(cancelSelection: @escaping @Sendable () -> Void) {
        self.cancelSelection = cancelSelection
    }

    func cancel() {
        if finish() { cancelSelection() }
    }

    func onTermination(_ handler: @escaping @Sendable () -> Void) {
        let invoke = lock.withLock {
            if ended { return true }
            termination = handler
            return false
        }
        if invoke { handler() }
    }

    @discardableResult
    func finish() -> Bool {
        let result = lock.withLock { () -> (Bool, (@Sendable () -> Void)?) in
            guard !ended else { return (false, nil) }
            ended = true
            defer { termination = nil }
            return (true, termination)
        }
        result.1?()
        return result.0
    }
}
