import Foundation

/// Something the radio reported.
public enum RadioEvent: Sendable, Equatable {
    case stateChanged(RadioState)
    case discovered(DiscoveredDevice)
    case connected(PeripheralID)
    case failedToConnect(PeripheralID, RadioError?)
    case disconnected(PeripheralID, RadioError?)
    /// The protocol version checked out and the encrypted read that pairs (or
    /// re-encrypts) was issued.
    case pairingStarted(PeripheralID)
    /// The companion service was found, the protocol version is supported, the
    /// encrypted pairing characteristic was read (so the link is paired), and
    /// notifications were requested.
    /// `nil` means success.
    case prepared(PeripheralID, RadioError?)
    case wrote(PeripheralID, GATTUUID, RadioError?)
    /// The answer to `read(_:on:)`.
    case read(PeripheralID, GATTUUID, Result<Data, RadioError>)
    case received(PeripheralID, GATTUUID, Data)
    /// iOS relaunched the app for a Bluetooth event and handed back the
    /// peripherals it was tracking.
    case restored([RestoredPeripheral])
}

public struct RestoredPeripheral: Sendable, Equatable {
    public let id: PeripheralID
    public let isConnected: Bool

    public init(id: PeripheralID, isConnected: Bool) {
        self.id = id
        self.isConnected = isConnected
    }
}

/// The Bluetooth radio, abstracted so the connection logic can run against
/// CoreBluetooth or the in-memory `FakeRadio`. Calls and events happen on the
/// main actor.
@MainActor
public protocol BLERadio: AnyObject {
    var onEvent: (@MainActor (RadioEvent) -> Void)? { get set }
    var state: RadioState { get }

    func startScan(for service: GATTUUID)
    func stopScan()
    /// Whether iOS can hand back this peripheral without scanning
    /// (`retrievePeripherals(withIdentifiers:)`).
    func isKnownPeripheral(_ id: PeripheralID) -> Bool
    /// Starts a connection. Like CoreBluetooth, a request stays pending until the
    /// peripheral is in range; it does not time out.
    func connect(_ id: PeripheralID)
    func cancelConnection(_ id: PeripheralID)
    /// Discovers the companion service, reads device info and checks the
    /// protocol major version, reads the encrypted pairing characteristic (which
    /// pairs or re-encrypts), then subscribes to notifications. Reports `.prepared`.
    func prepare(_ id: PeripheralID, configuration: CompanionServiceConfiguration)
    /// Writes with response. Reports `.wrote`.
    func write(_ data: Data, to characteristic: GATTUUID, on id: PeripheralID)
    /// Reads the characteristic's whole value (Read, then Read Blob for long
    /// values). Reports `.read`.
    func read(_ characteristic: GATTUUID, on id: PeripheralID)
    func maximumWriteLength(for id: PeripheralID) -> Int
    func name(for id: PeripheralID) -> String?
}
