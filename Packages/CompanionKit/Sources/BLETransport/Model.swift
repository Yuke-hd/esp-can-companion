import Foundation

/// The identifier iOS assigns to a peripheral (`CBPeripheral.identifier`).
/// Stable for a given phone and controller pair, so it is what we remember.
public typealias PeripheralID = UUID

/// A GATT service or characteristic UUID, kept as a string so the core
/// logic does not depend on CoreBluetooth.
public struct GATTUUID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let string: String

    public init(_ string: String) {
        self.string = string.uppercased()
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { string }
}

/// The controller's companion service and the characteristics the app may use.
///
/// The app only ever talks to this service. Writes to any characteristic that
/// is not listed in `writableCharacteristicUUIDs` are rejected before they
/// reach the radio, so nothing the app sends can be addressed elsewhere.
public struct CompanionServiceConfiguration: Sendable, Equatable {
    /// Service UUID used to filter scans and to find the service after connecting.
    public var serviceUUID: GATTUUID
    /// An encrypted characteristic. Reading it makes iOS start pairing if the
    /// phone and controller are not bonded yet.
    public var pairingCharacteristicUUID: GATTUUID
    /// Characteristics the app is allowed to write (always with response).
    public var writableCharacteristicUUIDs: Set<GATTUUID>
    /// Characteristics the app subscribes to for notifications.
    public var notifyingCharacteristicUUIDs: Set<GATTUUID>

    public init(
        serviceUUID: GATTUUID,
        pairingCharacteristicUUID: GATTUUID,
        writableCharacteristicUUIDs: Set<GATTUUID>,
        notifyingCharacteristicUUIDs: Set<GATTUUID>
    ) {
        self.serviceUUID = serviceUUID
        self.pairingCharacteristicUUID = pairingCharacteristicUUID
        self.writableCharacteristicUUIDs = writableCharacteristicUUIDs
        self.notifyingCharacteristicUUIDs = notifyingCharacteristicUUIDs
    }

    // TODO: Replace with the UUIDs from the firmware protocol spec
    // (Yuke-hd/mazda-can-accessory-controller#160) once it is published.
    // These are placeholders so the app, previews, and tests can run today.
    public static let placeholderControlCharacteristic: GATTUUID = "6E400002-0C1E-4C0B-9D1A-5CA1AB1E0001"
    public static let placeholderTelemetryCharacteristic: GATTUUID = "6E400003-0C1E-4C0B-9D1A-5CA1AB1E0001"
    public static let placeholderPairingCharacteristic: GATTUUID = "6E400004-0C1E-4C0B-9D1A-5CA1AB1E0001"

    public static let placeholder = CompanionServiceConfiguration(
        serviceUUID: "6E400001-0C1E-4C0B-9D1A-5CA1AB1E0001",
        pairingCharacteristicUUID: placeholderPairingCharacteristic,
        writableCharacteristicUUIDs: [placeholderControlCharacteristic],
        notifyingCharacteristicUUIDs: [placeholderTelemetryCharacteristic]
    )
}

/// The phone's Bluetooth radio and permission state.
public enum RadioState: Sendable, Equatable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

/// A controller seen while scanning.
public struct DiscoveredDevice: Identifiable, Sendable, Equatable {
    public let id: PeripheralID
    public var name: String?
    public var rssi: Int

    public init(id: PeripheralID, name: String?, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

/// The controller the app is connected and paired with.
public struct ConnectedDevice: Identifiable, Sendable, Equatable {
    public let id: PeripheralID
    public var name: String?
    /// Largest payload a single write with response can carry. iOS negotiates
    /// the ATT MTU itself, so this is the result of that negotiation.
    public var maximumWriteLength: Int

    public init(id: PeripheralID, name: String?, maximumWriteLength: Int) {
        self.id = id
        self.name = name
        self.maximumWriteLength = maximumWriteLength
    }
}

/// Why the link to the controller is down.
public enum DisconnectReason: Sendable, Equatable {
    /// The user disconnected or forgot the device.
    case userRequested
    /// An established link dropped, for example the controller lost power or
    /// went out of range.
    case connectionLost(String?)
    /// iOS reported an error while connecting.
    case connectFailed(String?)
    /// Pairing was cancelled, rejected, or timed out.
    case pairingFailed(String?)
    /// The controller no longer has a bond with this phone (its bonds were
    /// cleared). The user needs to forget the device in iOS Settings and pair again.
    case bondRemoved
    /// The peripheral does not expose the companion service.
    case incompatibleDevice
}

/// Connection state of the BLE link to a companion controller, as the UI sees it.
///
/// This module only owns moving bytes over BLE and never interprets protocol messages.
public enum LinkState: Sendable, Equatable {
    /// The radio state is not known yet, or Bluetooth is resetting.
    case unknown
    /// This device has no Bluetooth LE.
    case unsupported
    /// The user has not allowed Bluetooth access.
    case unauthorized
    /// Bluetooth is turned off.
    case poweredOff
    /// Bluetooth is on and there is no device to connect to.
    case idle
    /// Looking for controllers.
    case scanning
    /// Waiting for the controller to accept a connection. On iOS a connection
    /// request never times out, so this also covers "waiting for it to come in range".
    case connecting(PeripheralID)
    /// Connected, discovering the companion service and pairing.
    case pairing(PeripheralID)
    /// Connected, paired, and ready for traffic.
    case connected(ConnectedDevice)
    /// The link is down. `willReconnect` says whether the manager is already
    /// trying to get it back on its own.
    case disconnected(DisconnectReason, willReconnect: Bool)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Errors the radio reports to the manager.
public enum RadioError: Error, Sendable, Equatable {
    case pairingFailed(String?)
    case peerRemovedPairingInformation
    case serviceNotFound
    case characteristicNotFound(GATTUUID)
    case other(String?)

    var message: String? {
        switch self {
        case .pairingFailed(let message), .other(let message): message
        case .peerRemovedPairingInformation: "The controller removed its pairing information."
        case .serviceNotFound: "The companion service was not found."
        case .characteristicNotFound(let uuid): "Characteristic \(uuid) was not found."
        }
    }
}

/// Errors from `ConnectionManager.write(_:to:)`.
public enum ConnectionError: Error, Sendable, Equatable {
    case notConnected
    /// The characteristic is not one the companion service allows writes to.
    case characteristicNotWritable(GATTUUID)
    case payloadTooLarge(size: Int, maximum: Int)
    case writeFailed(RadioError)
    /// The link dropped before the controller acknowledged the write.
    case disconnected
}
