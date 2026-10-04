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
