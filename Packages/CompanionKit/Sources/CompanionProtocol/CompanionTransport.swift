import Foundation

/// The companion service characteristics, by role. The transport maps them to
/// GATT UUIDs, so this module needs no CoreBluetooth types.
public enum CompanionCharacteristic: Hashable, Sendable, CaseIterable {
    case deviceInfo
    case config
    case configStatus
    case liveSignals
    case command
}

/// Why a transport operation failed.
public enum CompanionTransportError: Error, Equatable, Sendable {
    /// No link to a paired controller.
    case notConnected
    /// The link dropped before the controller answered.
    case disconnected
    /// The controller answered with an ATT error response.
    case att(ATTError)
    /// Any other failure, such as a CoreBluetooth error.
    case other(String?)
}

/// A live notification subscription. Cancel it to stop receiving values.
public protocol CompanionSubscription: Sendable {
    func cancel()
}

/// Moves bytes to and from the companion service of one connected, paired
/// controller. The BLE layer implements it; tests use an in-memory controller.
public protocol CompanionTransport: AnyObject, Sendable {
    /// Reads a characteristic's whole value (Read and Read Blob).
    func read(_ characteristic: CompanionCharacteristic) async throws -> Data
    /// Writes with response. Throws `CompanionTransportError`.
    func write(_ value: Data, to characteristic: CompanionCharacteristic) async throws
    /// The largest single ATT write value on this link (`MTU - 3`).
    func maximumWriteLength() async throws -> Int
    /// Calls `handler` for each notification of `characteristic`, in arrival
    /// order and before the response to any write that the controller answered
    /// after sending the notification.
    func subscribe(
        to characteristic: CompanionCharacteristic,
        handler: @escaping @Sendable (Data) -> Void
    ) -> CompanionSubscription
}
