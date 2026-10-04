#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

/// `BLERadio` backed by CoreBluetooth.
///
/// Create one per app, early in launch: with a restore identifier, iOS can
/// relaunch the app in the background when the controller comes back in range
/// and hand back the pending connection (`bluetooth-central` background mode).
@MainActor
public final class CoreBluetoothRadio: NSObject, BLERadio {
    public static let defaultRestoreIdentifier = "BLETransport.central"

    public var onEvent: (@MainActor (RadioEvent) -> Void)?

    private var central: CBCentralManager!
    private var peripherals: [PeripheralID: CBPeripheral] = [:]
    private var configuration: CompanionServiceConfiguration?
    /// Peripherals still waiting for the pairing read to finish.
    private var preparing: Set<PeripheralID> = []

    public init(restoreIdentifier: String? = CoreBluetoothRadio.defaultRestoreIdentifier) {
        super.init()
        var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: true]
        #if os(iOS)
        if let restoreIdentifier {
            options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier
        }
        #endif
        central = CBCentralManager(delegate: self, queue: .main, options: options)
    }

    public var state: RadioState {
        switch central.state {
        case .poweredOn: .poweredOn
        case .poweredOff: .poweredOff
        case .unauthorized: .unauthorized
        case .unsupported: .unsupported
        case .resetting: .resetting
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }

    public func startScan(for service: GATTUUID) {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [CBUUID(string: service.string)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func stopScan() {
        guard central.state == .poweredOn else { return }
        central.stopScan()
    }

    public func isKnownPeripheral(_ id: PeripheralID) -> Bool {
        if peripherals[id] != nil { return true }
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else { return false }
        track(peripheral)
        return true
    }

    public func connect(_ id: PeripheralID) {
        guard let peripheral = peripherals[id] else { return }
        central.connect(peripheral, options: nil)
    }

    public func cancelConnection(_ id: PeripheralID) {
        preparing.remove(id)
        guard let peripheral = peripherals[id] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    public func prepare(_ id: PeripheralID, configuration: CompanionServiceConfiguration) {
        guard let peripheral = peripherals[id] else { return }
        self.configuration = configuration
        preparing.insert(id)
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: configuration.serviceUUID.string)])
    }

    public func write(_ data: Data, to characteristic: GATTUUID, on id: PeripheralID) {
        guard let peripheral = peripherals[id], let target = self.characteristic(characteristic, on: peripheral) else {
            emit(.wrote(id, characteristic, .characteristicNotFound(characteristic)))
            return
        }
        peripheral.writeValue(data, for: target, type: .withResponse)
    }

    public func maximumWriteLength(for id: PeripheralID) -> Int {
        peripherals[id]?.maximumWriteValueLength(for: .withResponse) ?? 20
    }

    public func name(for id: PeripheralID) -> String? {
        peripherals[id]?.name
    }

    // MARK: Helpers

    private func track(_ peripheral: CBPeripheral) {
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
    }

    private func emit(_ event: RadioEvent) {
        onEvent?(event)
    }

    private func companionService(on peripheral: CBPeripheral) -> CBService? {
        guard let configuration else { return nil }
        let uuid = CBUUID(string: configuration.serviceUUID.string)
        return peripheral.services?.first { $0.uuid == uuid }
    }

    private func characteristic(_ uuid: GATTUUID, on peripheral: CBPeripheral) -> CBCharacteristic? {
        let cbUUID = CBUUID(string: uuid.string)
        return companionService(on: peripheral)?.characteristics?.first { $0.uuid == cbUUID }
    }

    private func gattUUID(_ characteristic: CBCharacteristic) -> GATTUUID {
        GATTUUID(characteristic.uuid.uuidString)
    }

    private func finishPreparing(_ id: PeripheralID, _ error: RadioError?) {
        guard preparing.remove(id) != nil else { return }
        emit(.prepared(id, error))
    }

    static func radioError(_ error: Error?) -> RadioError? {
        guard let error else { return nil }
        let nsError = error as NSError
        if nsError.domain == CBErrorDomain, let code = CBError.Code(rawValue: nsError.code) {
            switch code {
            case .peerRemovedPairingInformation:
                return .peerRemovedPairingInformation
            case .encryptionTimedOut:
                return .pairingFailed(error.localizedDescription)
            default:
                break
            }
        }
        if nsError.domain == CBATTErrorDomain, let code = CBATTError.Code(rawValue: nsError.code) {
            switch code {
            case .insufficientAuthentication, .insufficientEncryption, .insufficientEncryptionKeySize, .insufficientAuthorization:
                return .pairingFailed(error.localizedDescription)
            default:
                break
            }
        }
        return .other(error.localizedDescription)
    }
}

// MARK: - CBCentralManagerDelegate

extension CoreBluetoothRadio: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            emit(.stateChanged(state))
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
            for peripheral in restored { track(peripheral) }
            emit(.restored(restored.map { RestoredPeripheral(id: $0.identifier, isConnected: $0.state == .connected) }))
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        MainActor.assumeIsolated {
            track(peripheral)
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            emit(.discovered(DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)))
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            emit(.connected(peripheral.identifier))
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            emit(.failedToConnect(peripheral.identifier, Self.radioError(error)))
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            preparing.remove(peripheral.identifier)
            emit(.disconnected(peripheral.identifier, Self.radioError(error)))
        }
    }
}

// MARK: - CBPeripheralDelegate

extension CoreBluetoothRadio: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            if let error {
                finishPreparing(id, Self.radioError(error))
                return
            }
            guard let service = companionService(on: peripheral) else {
                finishPreparing(id, .serviceNotFound)
                return
            }
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            guard let configuration else { return }
            if let error {
                finishPreparing(id, Self.radioError(error))
                return
            }
            guard let pairing = characteristic(configuration.pairingCharacteristicUUID, on: peripheral) else {
                finishPreparing(id, .characteristicNotFound(configuration.pairingCharacteristicUUID))
                return
            }
            for uuid in configuration.notifyingCharacteristicUUIDs {
                if let notifying = characteristic(uuid, on: peripheral) {
                    peripheral.setNotifyValue(true, for: notifying)
                }
            }
            // Reading an encrypted characteristic makes iOS pair (showing its
            // prompt) if needed; the read completes once the link is encrypted.
            peripheral.readValue(for: pairing)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            let uuid = gattUUID(characteristic)
            if preparing.contains(id), uuid == configuration?.pairingCharacteristicUUID {
                finishPreparing(id, Self.radioError(error))
                return
            }
            guard error == nil, let value = characteristic.value else { return }
            emit(.received(id, uuid, value))
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            emit(.wrote(peripheral.identifier, gattUUID(characteristic), Self.radioError(error)))
        }
    }
}
#endif
