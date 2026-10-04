import Foundation

/// A simulated companion controller for `FakeRadio`. All values are synthetic.
public struct FakeController: Sendable {
    public enum Pairing: Sendable, Equatable {
        case succeeds
        /// The user cancelled the iOS pairing prompt, or the passkey was wrong.
        case fails(String)
        /// The controller's bonds were cleared but the phone still has one.
        case peerRemovedPairingInformation
        /// The link drops mid-pairing without a pairing error, as ESP32 stacks
        /// often do when the user cancels the prompt.
        case dropsLink
    }

    public let id: PeripheralID
    public var name: String
    public var rssi: Int
    /// Powered and in range: advertising and accepting connections.
    public var isPoweredOn: Bool
    /// Whether iOS can retrieve it by identifier without scanning first.
    public var isKnownToSystem: Bool
    public var pairing: Pairing
    public var hasCompanionService: Bool
    /// When set, connection attempts fail with this error instead of connecting.
    public var connectError: RadioError?
    public var maximumWriteLength: Int

    public init(
        id: PeripheralID = UUID(),
        name: String = "Demo Controller",
        rssi: Int = -58,
        isPoweredOn: Bool = true,
        isKnownToSystem: Bool = true,
        pairing: Pairing = .succeeds,
        hasCompanionService: Bool = true,
        connectError: RadioError? = nil,
        maximumWriteLength: Int = 182
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isPoweredOn = isPoweredOn
        self.isKnownToSystem = isKnownToSystem
        self.pairing = pairing
        self.hasCompanionService = hasCompanionService
        self.connectError = connectError
        self.maximumWriteLength = maximumWriteLength
    }
}

/// An in-memory radio with protocol-shaped fake controllers, for previews,
/// the Simulator, and unit tests. It mimics CoreBluetooth's behavior: connection
/// requests stay pending until the controller is powered, turning Bluetooth off
/// drops everything without per-peripheral callbacks, and every response
/// arrives asynchronously through the scheduler.
@MainActor
public final class FakeRadio: BLERadio {
    public var onEvent: (@MainActor (RadioEvent) -> Void)?
    public private(set) var state: RadioState

    public private(set) var controllers: [PeripheralID: FakeController]
    public private(set) var isScanning = false
    public private(set) var pendingConnections: Set<PeripheralID> = []
    public private(set) var connectedPeripherals: Set<PeripheralID> = []
    /// Every write the controllers acknowledged, in order.
    public private(set) var receivedWrites: [(peripheral: PeripheralID, characteristic: GATTUUID, data: Data)] = []
    /// Return an error to make the controller reject a write.
    public var writeHandler: (@MainActor (GATTUUID, Data) -> RadioError?)?

    private let scheduler: BLEScheduler
    private let latency: TimeInterval
    private var configuration: CompanionServiceConfiguration?

    public init(
        controllers: [FakeController] = [FakeController()],
        state: RadioState = .poweredOn,
        scheduler: BLEScheduler,
        latency: TimeInterval = 0.05
    ) {
        self.controllers = Dictionary(uniqueKeysWithValues: controllers.map { ($0.id, $0) })
        self.state = state
        self.scheduler = scheduler
        self.latency = latency
    }

    // MARK: BLERadio

    public func startScan(for service: GATTUUID) {
        guard state == .poweredOn else { return }
        isScanning = true
        for controller in controllers.values where controller.isPoweredOn && controller.hasCompanionService {
            advertise(controller.id)
        }
    }

    public func stopScan() {
        isScanning = false
    }

    public func isKnownPeripheral(_ id: PeripheralID) -> Bool {
        controllers[id]?.isKnownToSystem ?? false
    }

    public func connect(_ id: PeripheralID) {
        guard state == .poweredOn, controllers[id] != nil, !connectedPeripherals.contains(id) else { return }
        pendingConnections.insert(id)
        if controllers[id]?.isPoweredOn == true { completeConnection(id) }
    }

    public func cancelConnection(_ id: PeripheralID) {
        pendingConnections.remove(id)
        if connectedPeripherals.remove(id) != nil {
            emit(.disconnected(id, nil))
        }
    }

    public func prepare(_ id: PeripheralID, configuration: CompanionServiceConfiguration) {
        self.configuration = configuration
        later { [self] in
            guard connectedPeripherals.contains(id), let controller = controllers[id] else { return }
            guard controller.hasCompanionService else {
                onEvent?(.prepared(id, .serviceNotFound))
                return
            }
            switch controller.pairing {
            case .succeeds: onEvent?(.prepared(id, nil))
            case .fails(let message): onEvent?(.prepared(id, .pairingFailed(message)))
            case .peerRemovedPairingInformation: onEvent?(.prepared(id, .peerRemovedPairingInformation))
            case .dropsLink:
                connectedPeripherals.remove(id)
                onEvent?(.disconnected(id, .other("The specified device has disconnected from us.")))
            }
        }
    }

    public func write(_ data: Data, to characteristic: GATTUUID, on id: PeripheralID) {
        later { [self] in
            guard connectedPeripherals.contains(id) else { return }
            guard configuration?.writableCharacteristicUUIDs.contains(characteristic) == true else {
                onEvent?(.wrote(id, characteristic, .characteristicNotFound(characteristic)))
                return
            }
            let error = writeHandler?(characteristic, data)
            if error == nil { receivedWrites.append((id, characteristic, data)) }
            onEvent?(.wrote(id, characteristic, error))
        }
    }

    public func maximumWriteLength(for id: PeripheralID) -> Int {
        controllers[id]?.maximumWriteLength ?? 20
    }

    public func name(for id: PeripheralID) -> String? {
        controllers[id]?.name
    }

    // MARK: Simulation controls

    public func setRadioState(_ newState: RadioState) {
        state = newState
        if newState != .poweredOn {
            isScanning = false
            pendingConnections.removeAll()
            connectedPeripherals.removeAll()
        }
        emit(.stateChanged(newState))
    }

    /// Adds a controller, or replaces one with the same id.
    public func addController(_ controller: FakeController) {
        controllers[controller.id] = controller
        if controller.isPoweredOn, isScanning { advertise(controller.id) }
    }

    public func update(_ id: PeripheralID, _ change: (inout FakeController) -> Void) {
        guard var controller = controllers[id] else { return }
        change(&controller)
        controllers[id] = controller
    }

    /// Cuts power to the controller, like switching off the car. An open link
    /// drops with a supervision timeout.
    public func powerOff(_ id: PeripheralID) {
        update(id) { $0.isPoweredOn = false }
        if connectedPeripherals.remove(id) != nil {
            emit(.disconnected(id, .other("The connection has timed out unexpectedly.")))
        }
    }

    public func powerOn(_ id: PeripheralID) {
        update(id) { $0.isPoweredOn = true }
        if isScanning { advertise(id) }
        if pendingConnections.contains(id) { completeConnection(id) }
    }

    public func powerCycle(_ id: PeripheralID, offFor duration: TimeInterval = 2) {
        powerOff(id)
        scheduler.schedule(after: duration) { [weak self] in self?.powerOn(id) }
    }

    /// Drops an open link while the controller stays powered, like brief
    /// interference. Pass an error to mimic how iOS reports the drop.
    public func dropConnection(
        _ id: PeripheralID,
        error: RadioError = .other("The specified device has disconnected from us.")
    ) {
        if connectedPeripherals.remove(id) != nil {
            emit(.disconnected(id, error))
        }
    }

    public func sendNotification(from id: PeripheralID, characteristic: GATTUUID, data: Data) {
        guard connectedPeripherals.contains(id) else { return }
        emit(.received(id, characteristic, data))
    }

    /// Simulates iOS relaunching the app in the background and restoring the
    /// central manager. Send it before the radio reports `.poweredOn`, as iOS does.
    public func restore(_ peripherals: [RestoredPeripheral]) {
        for peripheral in peripheralsToRestore(peripherals) where peripheral.isConnected {
            connectedPeripherals.insert(peripheral.id)
        }
        emit(.restored(peripherals))
    }

    // MARK: Private

    private func peripheralsToRestore(_ peripherals: [RestoredPeripheral]) -> [RestoredPeripheral] {
        peripherals.filter { controllers[$0.id] != nil }
    }

    private func advertise(_ id: PeripheralID) {
        later { [self] in
            guard isScanning, let controller = controllers[id], controller.isPoweredOn else { return }
            controllers[id]?.isKnownToSystem = true
            onEvent?(.discovered(DiscoveredDevice(id: id, name: controller.name, rssi: controller.rssi)))
        }
    }

    private func completeConnection(_ id: PeripheralID) {
        later { [self] in
            guard pendingConnections.contains(id), let controller = controllers[id], controller.isPoweredOn else { return }
            pendingConnections.remove(id)
            if let error = controller.connectError {
                onEvent?(.failedToConnect(id, error))
            } else {
                connectedPeripherals.insert(id)
                onEvent?(.connected(id))
            }
        }
    }

    private func emit(_ event: RadioEvent) {
        later { [self] in onEvent?(event) }
    }

    private func later(_ work: @escaping @MainActor () -> Void) {
        scheduler.schedule(after: latency, work)
    }
}

extension ConnectionManager {
    /// A manager backed by `FakeRadio` with one synthetic controller, for SwiftUI
    /// previews and running in the Simulator without hardware.
    public static func demo(autoConnect: Bool = true) -> ConnectionManager {
        let scheduler = MainActorScheduler()
        let controller = FakeController(name: "Demo Controller")
        let radio = FakeRadio(controllers: [controller], scheduler: scheduler, latency: 0.4)
        let manager = ConnectionManager(
            radio: radio,
            store: InMemoryDeviceStore(rememberedDeviceID: autoConnect ? controller.id : nil),
            scheduler: scheduler
        )
        manager.start()
        return manager
    }
}
