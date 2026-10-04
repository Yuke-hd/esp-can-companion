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
    /// Readable without pairing. Its first byte is the protocol major version,
    /// checked before pairing so the app never pairs with firmware it cannot talk to.
    public var deviceInfoCharacteristicUUID: GATTUUID
    /// Protocol major versions this app supports.
    public var supportedProtocolMajors: Set<UInt8>
    /// An encrypted, readable characteristic. Reading it makes iOS pair (or
    /// re-encrypt with a stored bond) before the read completes.
    public var pairingCharacteristicUUID: GATTUUID
    /// Characteristics the app is allowed to write (always with response).
    public var writableCharacteristicUUIDs: Set<GATTUUID>
    /// Characteristics the app is allowed to read once the link is paired.
    public var readableCharacteristicUUIDs: Set<GATTUUID>
    /// Characteristics the app subscribes to once the link is paired.
    public var notifyingCharacteristicUUIDs: Set<GATTUUID>
    /// Subscribed only when device info reports a supported live-signal layout
    /// (`live_signal_layout_version`, byte 4).
    public var liveSignalsCharacteristicUUID: GATTUUID?
    public var supportedLiveSignalLayouts: Set<UInt8>

    public init(
        serviceUUID: GATTUUID,
        deviceInfoCharacteristicUUID: GATTUUID,
        supportedProtocolMajors: Set<UInt8>,
        pairingCharacteristicUUID: GATTUUID,
        writableCharacteristicUUIDs: Set<GATTUUID>,
        readableCharacteristicUUIDs: Set<GATTUUID> = [],
        notifyingCharacteristicUUIDs: Set<GATTUUID>,
        liveSignalsCharacteristicUUID: GATTUUID? = nil,
        supportedLiveSignalLayouts: Set<UInt8> = []
    ) {
        self.serviceUUID = serviceUUID
        self.deviceInfoCharacteristicUUID = deviceInfoCharacteristicUUID
        self.supportedProtocolMajors = supportedProtocolMajors
        self.pairingCharacteristicUUID = pairingCharacteristicUUID
        self.writableCharacteristicUUIDs = writableCharacteristicUUIDs
        self.readableCharacteristicUUIDs = readableCharacteristicUUIDs
        self.notifyingCharacteristicUUIDs = notifyingCharacteristicUUIDs
        self.liveSignalsCharacteristicUUID = liveSignalsCharacteristicUUID
        self.supportedLiveSignalLayouts = supportedLiveSignalLayouts
    }
}

/// UUIDs from the companion BLE protocol, version 1
/// (Yuke-hd/mazda-can-accessory-controller, docs/specs/companion/ble-protocol.md).
/// They are fixed for every protocol version.
public enum CompanionGATT {
    public static let service: GATTUUID = "AB490000-09B6-4509-BF8E-2790253BAF98"
    /// Read, no security.
    public static let deviceInfo: GATTUUID = "AB490001-09B6-4509-BF8E-2790253BAF98"
    /// Read and write, encrypted and bonded.
    public static let config: GATTUUID = "AB490002-09B6-4509-BF8E-2790253BAF98"
    /// Read and notify, encrypted and bonded.
    public static let configStatus: GATTUUID = "AB490003-09B6-4509-BF8E-2790253BAF98"
    /// Notify, encrypted and bonded.
    public static let liveSignals: GATTUUID = "AB490004-09B6-4509-BF8E-2790253BAF98"
    /// Write, encrypted and bonded.
    public static let command: GATTUUID = "AB490005-09B6-4509-BF8E-2790253BAF98"
}

extension CompanionServiceConfiguration {
    /// Protocol version 1. Config status is the pairing trigger because it is
    /// the cheapest encrypted read.
    public static let protocolV1 = CompanionServiceConfiguration(
        serviceUUID: CompanionGATT.service,
        deviceInfoCharacteristicUUID: CompanionGATT.deviceInfo,
        supportedProtocolMajors: [1],
        pairingCharacteristicUUID: CompanionGATT.configStatus,
        writableCharacteristicUUIDs: [CompanionGATT.config, CompanionGATT.command],
        readableCharacteristicUUIDs: [CompanionGATT.deviceInfo, CompanionGATT.config, CompanionGATT.configStatus],
        notifyingCharacteristicUUIDs: [CompanionGATT.configStatus, CompanionGATT.liveSignals],
        liveSignalsCharacteristicUUID: CompanionGATT.liveSignals,
        supportedLiveSignalLayouts: [1]
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
    /// Largest payload a single ATT Write Request can carry (`MTU - 3`). iOS
    /// negotiates the ATT MTU itself, so this is the result of that negotiation.
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
    /// The controller speaks a protocol major version this app does not
    /// support. The app or the firmware needs an update; the app did not pair.
    case unsupportedProtocol(major: UInt8)
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
    case unsupportedProtocol(major: UInt8)
    /// The controller answered a read or write with this ATT error code,
    /// including the protocol's application codes (`0x80`–`0x9F`).
    case att(UInt8)
    case other(String?)

    var message: String? {
        switch self {
        case .pairingFailed(let message), .other(let message): message
        case .peerRemovedPairingInformation: "The controller removed its pairing information."
        case .serviceNotFound: "The companion service was not found."
        case .characteristicNotFound(let uuid): "Characteristic \(uuid) was not found."
        case .unsupportedProtocol(let major): "Unsupported protocol version \(major)."
        case .att(let code): "The controller answered with ATT error \(code)."
        }
    }
}

/// Errors from `ConnectionManager.write(_:to:)` and `read(_:)`.
public enum ConnectionError: Error, Sendable, Equatable {
    case notConnected
    /// The characteristic is not one the companion service allows writes to.
    case characteristicNotWritable(GATTUUID)
    /// The characteristic is not one the companion service allows reads from.
    case characteristicNotReadable(GATTUUID)
    case payloadTooLarge(size: Int, maximum: Int)
    case writeFailed(RadioError)
    case readFailed(RadioError)
    /// The link dropped before the controller answered the write or read.
    case disconnected
}
