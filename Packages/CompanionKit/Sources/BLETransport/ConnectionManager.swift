import Foundation
import Observation

/// Owns the link to one companion controller: scanning, connecting, pairing,
/// remembering the device, and reconnecting on its own when the link drops.
///
/// Observe `state` from SwiftUI. All work happens on the main actor.
@MainActor
@Observable
public final class ConnectionManager {
    /// Current link state.
    public private(set) var state: LinkState = .unknown
    /// Controllers seen since the last `startScan()`.
    public private(set) var discoveredDevices: [DiscoveredDevice] = []
    /// The controller the manager reconnects to on launch, if any.
    public private(set) var rememberedDeviceID: PeripheralID?

    public let configuration: CompanionServiceConfiguration

    /// Called for every notification from the companion service.
    @ObservationIgnored public var onNotification: (@MainActor (GATTUUID, Data) -> Void)?

    @ObservationIgnored private let radio: BLERadio
    @ObservationIgnored private let store: DeviceStore
    @ObservationIgnored private let scheduler: BLEScheduler
    @ObservationIgnored private let reconnectPolicy: ReconnectPolicy

    /// The device we want a link to.
    @ObservationIgnored private var target: PeripheralID?
    /// False after the user disconnects or pairing fails, so drops are not retried.
    @ObservationIgnored private var wantsLink = false
    @ObservationIgnored private var isScanRequested = false
    @ObservationIgnored private var isScanningForTarget = false
    /// A disconnect we caused ourselves and will handle with a backoff retry.
    @ObservationIgnored private var ignoreDisconnectFor: PeripheralID?
    @ObservationIgnored private var restoredConnected: Set<PeripheralID> = []
    @ObservationIgnored private var failedAttempts = 0
    /// Links dropped during pairing in a row. The controller drops the link when
    /// it rejects a pairing, for example outside its pairing window.
    @ObservationIgnored private var pairingDrops = 0
    /// Set once the encrypted read was issued on the current connection, so only
    /// failures of the pairing itself count toward `maximumPairingDrops`.
    @ObservationIgnored private var pairingStartedFor: PeripheralID?
    private static let maximumPairingDrops = 3
    @ObservationIgnored private var retryToken: BLECancellable?
    @ObservationIgnored private var pendingWrites: [GATTUUID: [CheckedContinuation<Void, Error>]] = [:]
    @ObservationIgnored private var started = false

    public init(
        radio: BLERadio,
        configuration: CompanionServiceConfiguration = .protocolV1,
        store: DeviceStore,
        scheduler: BLEScheduler,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy()
    ) {
        self.radio = radio
        self.configuration = configuration
        self.store = store
        self.scheduler = scheduler
        self.reconnectPolicy = reconnectPolicy
        self.rememberedDeviceID = store.rememberedDeviceID
    }

    // MARK: - Public API

    /// Starts listening to the radio and reconnects to the remembered device, if any.
    public func start() {
        guard !started else { return }
        started = true
        if target == nil, let remembered = store.rememberedDeviceID {
            target = remembered
            wantsLink = true
        }
        radio.onEvent = { [weak self] event in self?.handle(event) }
        handleRadioState(radio.state)
    }

    public func startScan() {
        isScanRequested = true
        discoveredDevices = []
        guard radio.state == .poweredOn else { return }
        radio.startScan(for: configuration.serviceUUID)
        if !isLinkActive { state = .scanning }
    }

    public func stopScan() {
        isScanRequested = false
        if !isScanningForTarget { radio.stopScan() }
        if state == .scanning { state = .idle }
    }

    /// Connects to a controller the user picked. It becomes the remembered
    /// device once pairing succeeds.
    public func connect(to id: PeripheralID) {
        stopScan()
        stopTargetScan()
        ignoreDisconnectFor = nil
        if let previous = target, previous != id {
            radio.cancelConnection(previous)
            failPendingWrites(.disconnected)
        }
        target = id
        wantsLink = true
        failedAttempts = 0
        pairingDrops = 0
        guard radio.state == .poweredOn else { return }
        attemptConnect(id)
    }

    /// Drops the link and stops reconnecting until `reconnect()` or `connect(to:)`.
    public func disconnect() {
        wantsLink = false
        cancelRetry()
        stopTargetScan()
        ignoreDisconnectFor = nil
        if let id = target { radio.cancelConnection(id) }
        failPendingWrites(.disconnected)
        state = .disconnected(.userRequested, willReconnect: false)
    }

    /// Resumes connecting to the current or remembered device, for example
    /// after a pairing failure the user has fixed.
    public func reconnect() {
        guard let id = target ?? store.rememberedDeviceID else { return }
        target = id
        wantsLink = true
        failedAttempts = 0
        pairingDrops = 0
        ignoreDisconnectFor = nil
        guard radio.state == .poweredOn else { return }
        attemptConnect(id)
    }

    /// Disconnects and forgets the remembered device.
    public func forgetDevice() {
        disconnect()
        target = nil
        store.rememberedDeviceID = nil
        rememberedDeviceID = nil
        if radio.state == .poweredOn { state = .idle }
    }

    /// Writes to a companion-service characteristic, with response.
    ///
    /// Only characteristics in `configuration.writableCharacteristicUUIDs` are
    /// accepted. Payloads larger than `maximumWriteLength` are rejected; framing
    /// large messages is the protocol client's job.
    public func write(_ data: Data, to characteristic: GATTUUID) async throws {
        guard configuration.writableCharacteristicUUIDs.contains(characteristic) else {
            throw ConnectionError.characteristicNotWritable(characteristic)
        }
        guard case .connected(let device) = state else {
            throw ConnectionError.notConnected
        }
        let maximum = radio.maximumWriteLength(for: device.id)
        guard data.count <= maximum else {
            throw ConnectionError.payloadTooLarge(size: data.count, maximum: maximum)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingWrites[characteristic, default: []].append(continuation)
            radio.write(data, to: characteristic, on: device.id)
        }
    }

    // MARK: - Events

    private func handle(_ event: RadioEvent) {
        switch event {
        case .stateChanged(let radioState):
            handleRadioState(radioState)

        case .discovered(let device):
            if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                discoveredDevices[index] = device
            } else {
                discoveredDevices.append(device)
            }
            if isScanningForTarget, device.id == target, wantsLink {
                isScanningForTarget = false
                if !isScanRequested { radio.stopScan() }
                radio.connect(device.id)
            }

        case .connected(let id):
            guard id == target, wantsLink else {
                radio.cancelConnection(id)
                return
            }
            state = .pairing(id)
            radio.prepare(id, configuration: configuration)

        case .failedToConnect(let id, let error):
            guard id == target, wantsLink else { return }
            if let error, let reason = Self.terminalReason(for: error) {
                stopReconnecting(id, reason: reason)
            } else {
                scheduleRetry(reason: .connectFailed(error?.message))
            }

        case .disconnected(let id, let error):
            guard id == target else { return }
            failPendingWrites(.disconnected)
            if ignoreDisconnectFor == id {
                ignoreDisconnectFor = nil
                return
            }
            guard wantsLink, radio.state == .poweredOn else { return }
            if let error, let reason = Self.terminalReason(for: error) {
                // iOS often reports a cleared bond or failed pairing as a disconnect.
                stopReconnecting(id, reason: reason)
            } else if case .connected = state {
                attemptConnect(id, showing: .connectionLost(error?.message))
            } else if !pairingFailureReachedLimit(id, message: error?.message) {
                // Dropped before the link was usable (for example during pairing):
                // back off so a failing controller does not cause a tight loop.
                scheduleRetry(reason: .connectionLost(error?.message))
            }

        case .pairingStarted(let id):
            guard id == target else { return }
            pairingStartedFor = id

        case .prepared(let id, let error):
            guard id == target, wantsLink else { return }
            handlePrepared(id, error: error)

        case .wrote(let id, let characteristic, let error):
            guard id == target, var queue = pendingWrites[characteristic], !queue.isEmpty else { return }
            let continuation = queue.removeFirst()
            pendingWrites[characteristic] = queue
            if let error {
                continuation.resume(throwing: ConnectionError.writeFailed(error))
            } else {
                continuation.resume()
            }

        case .received(let id, let characteristic, let data):
            guard id == target, state.isConnected else { return }
            onNotification?(characteristic, data)

        case .restored(let peripherals):
            // Prefer the remembered device; otherwise adopt whatever iOS was tracking.
            let match = peripherals.first { $0.id == store.rememberedDeviceID } ?? peripherals.first
            guard let match else { return }
            target = match.id
            wantsLink = true
            if match.isConnected { restoredConnected.insert(match.id) }
        }
    }

    private func handleRadioState(_ radioState: RadioState) {
        switch radioState {
        case .poweredOn:
            if isScanRequested {
                radio.startScan(for: configuration.serviceUUID)
            }
            if let id = target, wantsLink {
                if restoredConnected.remove(id) != nil {
                    state = .pairing(id)
                    radio.prepare(id, configuration: configuration)
                } else {
                    attemptConnect(id)
                }
            } else if isScanRequested {
                state = .scanning
            } else if case .disconnected = state {
                // Keep showing why the link is down.
            } else {
                state = .idle
            }
        case .poweredOff:
            radioWentAway(.poweredOff)
        case .unauthorized:
            radioWentAway(.unauthorized)
        case .unsupported:
            radioWentAway(.unsupported)
        case .unknown, .resetting:
            radioWentAway(.unknown)
        }
    }

    /// iOS drops every link and pending request when the radio goes away, and
    /// does not report each one. Keep the target so we reconnect when it is back.
    private func radioWentAway(_ newState: LinkState) {
        cancelRetry()
        isScanningForTarget = false
        ignoreDisconnectFor = nil
        failPendingWrites(.disconnected)
        state = newState
    }

    private func handlePrepared(_ id: PeripheralID, error: RadioError?) {
        guard let error else {
            failedAttempts = 0
            pairingDrops = 0
            store.rememberedDeviceID = id
            rememberedDeviceID = id
            state = .connected(ConnectedDevice(
                id: id,
                name: radio.name(for: id),
                maximumWriteLength: radio.maximumWriteLength(for: id)
            ))
            return
        }

        if let reason = Self.terminalReason(for: error) {
            stopReconnecting(id, reason: reason)
        } else if !pairingFailureReachedLimit(id, message: error.message) {
            ignoreDisconnectFor = id
            radio.cancelConnection(id)
            scheduleRetry(reason: .connectionLost(error.message))
        }
    }

    /// Counts a failure after the pairing read was issued. The controller drops
    /// the link when it rejects a pairing (for example outside its pairing
    /// window), so repeated failures there mean the user has to act. Returns
    /// true when it gave up.
    private func pairingFailureReachedLimit(_ id: PeripheralID, message: String?) -> Bool {
        guard pairingStartedFor == id else { return false }
        pairingStartedFor = nil
        pairingDrops += 1
        guard pairingDrops >= Self.maximumPairingDrops else { return false }
        pairingDrops = 0
        stopReconnecting(id, reason: .pairingFailed(message))
        return true
    }

    /// Errors that retrying cannot fix: it would only re-prompt or fail again.
    private static func terminalReason(for error: RadioError) -> DisconnectReason? {
        switch error {
        case .peerRemovedPairingInformation: .bondRemoved
        case .pairingFailed(let message): .pairingFailed(message)
        case .serviceNotFound, .characteristicNotFound: .incompatibleDevice
        case .unsupportedProtocol(let major): .unsupportedProtocol(major: major)
        case .other: nil
        }
    }

    /// Gives up on the target until the user acts.
    private func stopReconnecting(_ id: PeripheralID, reason: DisconnectReason) {
        wantsLink = false
        cancelRetry()
        stopTargetScan()
        radio.cancelConnection(id)
        state = .disconnected(reason, willReconnect: false)
    }

    // MARK: - Connecting

    private var isLinkActive: Bool {
        switch state {
        case .connecting, .pairing, .connected: true
        case .disconnected(_, let willReconnect): willReconnect
        default: false
        }
    }

    /// Requests a connection. With `reason`, the state keeps showing why the
    /// link went down while the request is pending.
    private func attemptConnect(_ id: PeripheralID, showing reason: DisconnectReason? = nil) {
        cancelRetry()
        pairingStartedFor = nil
        stopTargetScan()
        if let reason {
            state = .disconnected(reason, willReconnect: true)
        } else {
            state = .connecting(id)
        }
        if radio.isKnownPeripheral(id) {
            radio.connect(id)
        } else {
            // iOS no longer knows this identifier (for example after a reset);
            // find it by scanning for the companion service.
            isScanningForTarget = true
            radio.startScan(for: configuration.serviceUUID)
        }
    }

    private func scheduleRetry(reason: DisconnectReason) {
        failedAttempts += 1
        state = .disconnected(reason, willReconnect: true)
        cancelRetry()
        retryToken = scheduler.schedule(after: reconnectPolicy.delay(forAttempt: failedAttempts)) { [weak self] in
            guard let self, self.wantsLink, let id = self.target, self.radio.state == .poweredOn else { return }
            self.attemptConnect(id, showing: reason)
        }
    }

    private func stopTargetScan() {
        guard isScanningForTarget else { return }
        isScanningForTarget = false
        if !isScanRequested { radio.stopScan() }
    }

    private func cancelRetry() {
        retryToken?.cancel()
        retryToken = nil
    }

    private func failPendingWrites(_ error: ConnectionError) {
        let continuations = pendingWrites.values.flatMap { $0 }
        pendingWrites = [:]
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}
