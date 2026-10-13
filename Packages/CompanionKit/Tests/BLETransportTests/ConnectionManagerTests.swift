import XCTest
@testable import BLETransport

@MainActor
final class ConnectionManagerTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var controller: FakeController!
    private var radio: FakeRadio!
    private var store: InMemoryDeviceStore!
    private var manager: ConnectionManager!

    private let control = CompanionGATT.command
    private let telemetry = CompanionGATT.liveSignals

    private func makeManager(
        controllers: [FakeController]? = nil,
        radioState: RadioState = .poweredOn,
        remembered: PeripheralID? = nil,
        start: Bool = true
    ) {
        scheduler = ManualScheduler()
        controller = controllers?.first ?? FakeController(name: "Bench Controller")
        radio = FakeRadio(controllers: controllers ?? [controller], state: radioState, scheduler: scheduler, latency: 0.1)
        store = InMemoryDeviceStore(rememberedDeviceID: remembered)
        manager = ConnectionManager(radio: radio, store: store, scheduler: scheduler)
        if start { manager.start() }
    }

    private func connectAndPair() {
        manager.connect(to: controller.id)
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected, "expected connected, got \(manager.state)")
    }

    private func startWrite(_ data: Data) -> Task<Void, Error> {
        let manager = manager!
        let control = control
        return Task { @MainActor in try await manager.write(data, to: control) }
    }

    /// Lets a just-started write reach the fake radio, which queues its response.
    private func waitForRadioWork() async {
        for _ in 0..<1_000 where scheduler.nextDelay == nil {
            await Task.yield()
        }
        XCTAssertNotNil(scheduler.nextDelay, "the write never reached the radio")
    }

    private func finishSelection(_ task: Task<Void, Error>) async throws {
        await waitForRadioWork()
        for _ in 0..<100 { scheduler.runUntilIdle(); await Task.yield() }
        try await task.value
    }

    func testLiveNotifierIsExplicitAndSwitchDisablesBeforeEnabling() async throws {
        makeManager(); connectAndPair()
        XCTAssertNil(manager.selectedLiveNotifier)
        var received: [GATTUUID] = []
        manager.onNotification = { uuid, _ in received.append(uuid) }
        radio.sendNotification(from: controller.id, characteristic: telemetry, data: Data([1]))
        scheduler.runUntilIdle()
        XCTAssertTrue(received.isEmpty)
        try await finishSelection(Task { try await manager.selectLiveNotifier(telemetry) })
        try await finishSelection(Task { try await manager.selectLiveNotifier(CompanionGATT.extensibleLiveSignals) })
        XCTAssertEqual(radio.notificationRequests.suffix(3).map(\.characteristic), [telemetry, CompanionGATT.extensibleLiveSignals, CompanionGATT.extensibleLiveSignals])
        XCTAssertEqual(radio.notificationRequests.suffix(3).map(\.enabled), [false, false, true])
        // A restored or queued radio callback can arrive despite the remote gate.
        radio.onEvent?(.received(controller.id, telemetry, Data([2])))
        radio.sendNotification(from: controller.id, characteristic: CompanionGATT.extensibleLiveSignals, data: Data([3]))
        radio.sendNotification(from: controller.id, characteristic: CompanionGATT.configStatus, data: Data([4]))
        scheduler.runUntilIdle()
        XCTAssertEqual(received, [CompanionGATT.extensibleLiveSignals, CompanionGATT.configStatus])
        try await finishSelection(Task { try await manager.selectLiveNotifier(nil) })
        XCTAssertNil(manager.selectedLiveNotifier)
    }

    func testNotifierErrorUnsupportedAndDisconnect() async throws {
        makeManager(); connectAndPair()
        radio.notificationHandler = { _, enabled in enabled ? .att(3) : nil }
        do { try await finishSelection(Task { try await manager.selectLiveNotifier(telemetry) }); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? LiveNotifierError, .failed(.att(3))) }
        XCTAssertNil(manager.selectedLiveNotifier)
        do { try await manager.selectLiveNotifier(CompanionGATT.command); XCTFail("expected unsupported") }
        catch { XCTAssertEqual(error as? LiveNotifierError, .unsupported(CompanionGATT.command)) }
        radio.notificationHandler = nil
        try await finishSelection(Task { try await manager.selectLiveNotifier(CompanionGATT.extensibleLiveSignals) })
        XCTAssertEqual(radio.enabledNotifications[controller.id], [CompanionGATT.configStatus, CompanionGATT.extensibleLiveSignals])
        let pending = Task { try await manager.selectLiveNotifier(telemetry) }
        await waitForRadioWork()
        manager.disconnect(); scheduler.runUntilIdle()
        do { try await pending.value; XCTFail("expected disconnect") }
        catch { XCTAssertEqual(error as? LiveNotifierError, .disconnected) }
        XCTAssertTrue(manager.availableCharacteristics.isEmpty)
    }

    func testWrongNotificationStateCannotConfirmSelection() async throws {
        makeManager(); connectAndPair()
        radio.notificationReportedState = true
        do { try await finishSelection(Task { try await manager.selectLiveNotifier(telemetry) }); XCTFail("expected mismatched disable failure") }
        catch { XCTAssertEqual(error as? LiveNotifierError, .failed(.other("Notification state did not match request."))) }
        XCTAssertNil(manager.selectedLiveNotifier)
    }

    func testCancelledSelectionClosesLinkAndReconnectRequiresSelection() async throws {
        makeManager(); connectAndPair()
        let pending = Task { try await manager.selectLiveNotifier(telemetry) }
        radio.hangsNotificationRequests = true
        await waitForRadioWork(); scheduler.runUntilIdle(); pending.cancel()
        for _ in 0..<100 { await Task.yield() }
        scheduler.runUntilIdle()
        do { try await pending.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || error as? LiveNotifierError == .disconnected) }
        manager.reconnect(); scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
        XCTAssertNil(manager.selectedLiveNotifier)
        XCTAssertFalse(radio.enabledNotifications[controller.id, default: []].contains(telemetry))
    }

    func testRestoredSubscriptionsClearedAndMissingOptionalIsMetadata() async throws {
        var device = FakeController()
        device.availableCharacteristics.remove(CompanionGATT.extensibleLiveSignals)
        makeManager(controllers: [device], radioState: .unknown, remembered: device.id)
        radio.restore([RestoredPeripheral(id: device.id, isConnected: true)], notifying: [telemetry, CompanionGATT.extensibleLiveSignals])
        scheduler.runUntilIdle()
        radio.setRadioState(.poweredOn); scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
        XCTAssertNil(manager.selectedLiveNotifier)
        XCTAssertFalse(manager.availableCharacteristics.contains(CompanionGATT.extensibleLiveSignals))
        do { try await manager.selectLiveNotifier(CompanionGATT.extensibleLiveSignals); XCTFail("missing") }
        catch { XCTAssertEqual(error as? LiveNotifierError, .unsupported(CompanionGATT.extensibleLiveSignals)) }
    }

    // MARK: Radio and permission states

    func testRadioStatesMapToLinkStates() async {
        makeManager(radioState: .unknown)
        XCTAssertEqual(manager.state, .unknown)

        radio.setRadioState(.unauthorized)
        scheduler.runUntilIdle()
        XCTAssertEqual(manager.state, .unauthorized)

        radio.setRadioState(.poweredOff)
        scheduler.runUntilIdle()
        XCTAssertEqual(manager.state, .poweredOff)

        radio.setRadioState(.unsupported)
        scheduler.runUntilIdle()
        XCTAssertEqual(manager.state, .unsupported)

        radio.setRadioState(.poweredOn)
        scheduler.runUntilIdle()
        XCTAssertEqual(manager.state, .idle)
    }

    // MARK: Scanning and connecting

    func testScanFindsControllers() async {
        let second = FakeController(name: "Second Controller", rssi: -80)
        makeManager(controllers: [FakeController(name: "Bench Controller"), second])

        manager.startScan()
        XCTAssertEqual(manager.state, .scanning)
        scheduler.runUntilIdle()

        XCTAssertEqual(Set(manager.discoveredDevices.map(\.name)), ["Bench Controller", "Second Controller"])

        manager.stopScan()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(radio.isScanning)
    }

    func testScanIgnoresDevicesWithoutCompanionService() async {
        makeManager(controllers: [FakeController(name: "Other Device", hasCompanionService: false)])
        manager.startScan()
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.discoveredDevices.isEmpty)
    }

    func testConnectGoesThroughConnectingAndPairingAndRemembersDevice() async {
        makeManager()
        manager.connect(to: controller.id)
        XCTAssertEqual(manager.state, .connecting(controller.id))

        scheduler.advance(by: 0.1)
        XCTAssertEqual(manager.state, .pairing(controller.id))

        scheduler.advance(by: 0.1)
        XCTAssertEqual(manager.state, .connected(ConnectedDevice(id: controller.id, name: "Bench Controller", maximumWriteLength: 182)))
        XCTAssertEqual(store.rememberedDeviceID, controller.id)
        XCTAssertEqual(manager.rememberedDeviceID, controller.id)
    }

    func testConnectingToUnknownPeripheralScansForIt() async {
        makeManager(controllers: [FakeController(isKnownToSystem: false)])
        manager.connect(to: controller.id)
        XCTAssertEqual(manager.state, .connecting(controller.id))
        XCTAssertTrue(radio.isScanning)

        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
        XCTAssertFalse(radio.isScanning)
    }

    // MARK: Pairing failures

    func testPairingFailureIsSurfacedAndNotRetried() async {
        makeManager(controllers: [FakeController(pairing: .fails("Pairing cancelled"))])
        manager.connect(to: controller.id)
        scheduler.runUntilIdle()

        XCTAssertEqual(manager.state, .disconnected(.pairingFailed("Pairing cancelled"), willReconnect: false))
        XCTAssertNil(store.rememberedDeviceID)
        XCTAssertTrue(radio.connectedPeripherals.isEmpty)

        scheduler.advance(by: 60)
        XCTAssertEqual(manager.state, .disconnected(.pairingFailed("Pairing cancelled"), willReconnect: false))

        radio.update(controller.id) { $0.pairing = .succeeds }
        manager.reconnect()
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testClearedControllerBondIsSurfaced() async {
        makeManager()
        connectAndPair()

        radio.update(controller.id) { $0.pairing = .peerRemovedPairingInformation }
        radio.powerCycle(controller.id)
        scheduler.advance(by: 5)

        XCTAssertEqual(manager.state, .disconnected(.bondRemoved, willReconnect: false))
        // The device stays remembered; forgetting it is the user's call.
        XCTAssertEqual(store.rememberedDeviceID, controller.id)
    }

    func testBondRemovedReportedAsConnectFailureIsNotRetried() async {
        makeManager(controllers: [FakeController(connectError: .peerRemovedPairingInformation)])
        manager.connect(to: controller.id)
        scheduler.runUntilIdle()

        XCTAssertEqual(manager.state, .disconnected(.bondRemoved, willReconnect: false))
        XCTAssertNil(scheduler.nextDelay, "nothing should be scheduled to retry")
    }

    func testBondRemovedReportedAsDisconnectIsNotRetried() async {
        makeManager()
        connectAndPair()

        radio.dropConnection(controller.id, error: .peerRemovedPairingInformation)
        scheduler.runUntilIdle()

        XCTAssertEqual(manager.state, .disconnected(.bondRemoved, willReconnect: false))
        XCTAssertTrue(radio.pendingConnections.isEmpty)
    }

    func testLinkDroppingDuringPairingBacksOff() async {
        makeManager(controllers: [FakeController(pairing: .dropsLink)])
        manager.connect(to: controller.id)
        scheduler.advance(by: 0.2)

        guard case .disconnected(.connectionLost, willReconnect: true) = manager.state else {
            return XCTFail("expected connectionLost, got \(manager.state)")
        }
        XCTAssertTrue(radio.pendingConnections.isEmpty, "should wait before reconnecting")
        XCTAssertEqual(scheduler.nextDelay ?? -1, 1, accuracy: 0.001)

        // The retry (at 1.2 s) connects and drops again at 1.4 s; the next wait is 2 s.
        scheduler.advance(by: 1.3)
        XCTAssertTrue(radio.pendingConnections.isEmpty)
        XCTAssertEqual(scheduler.nextDelay ?? -1, 1.9, accuracy: 0.001)

        radio.update(controller.id) { $0.pairing = .succeeds }
        scheduler.advance(by: 2.5)
        XCTAssertTrue(manager.state.isConnected)
    }

    func testUnsupportedProtocolMajorIsRejectedBeforePairing() async {
        makeManager(controllers: [FakeController(protocolMajor: 2)])
        manager.connect(to: controller.id)
        scheduler.runUntilIdle()

        XCTAssertEqual(manager.state, .disconnected(.unsupportedProtocol(major: 2), willReconnect: false))
        XCTAssertNil(store.rememberedDeviceID)
    }

    func testRepeatedDropsDuringPairingStopRetrying() async {
        // For example the pairing window is closed: the controller rejects the
        // pairing and drops the link each time.
        makeManager(controllers: [FakeController(pairing: .dropsLink)])
        manager.connect(to: controller.id)
        scheduler.advance(by: 60)

        guard case .disconnected(.pairingFailed, willReconnect: false) = manager.state else {
            return XCTFail("expected pairingFailed, got \(manager.state)")
        }
        XCTAssertNil(scheduler.nextDelay)
    }

    func testDropsBeforePairingKeepRetryingForBondedPhone() async {
        makeManager()
        connectAndPair()

        radio.update(controller.id) { $0.dropsBeforePairing = true }
        radio.dropConnection(controller.id)
        scheduler.advance(by: 120)

        guard case .disconnected(.connectionLost, willReconnect: true) = manager.state else {
            return XCTFail("expected to keep retrying, got \(manager.state)")
        }

        radio.update(controller.id) { $0.dropsBeforePairing = false }
        scheduler.advance(by: 60)
        XCTAssertTrue(manager.state.isConnected)
    }

    func testDeviceWithoutCompanionServiceIsRejected() async {
        makeManager(controllers: [FakeController(hasCompanionService: false)])
        manager.connect(to: controller.id)
        scheduler.runUntilIdle()
        XCTAssertEqual(manager.state, .disconnected(.incompatibleDevice, willReconnect: false))
    }

    // MARK: Reconnecting

    func testReconnectsAfterControllerPowerCycles() async {
        makeManager()
        connectAndPair()

        radio.powerOff(controller.id)
        scheduler.runUntilIdle()
        guard case .disconnected(.connectionLost, willReconnect: true) = manager.state else {
            return XCTFail("expected connectionLost, got \(manager.state)")
        }
        XCTAssertTrue(radio.pendingConnections.contains(controller.id), "a connection request should be waiting")

        // Stays waiting however long the controller is off.
        scheduler.advance(by: 600)
        XCTAssertFalse(manager.state.isConnected)

        radio.powerOn(controller.id)
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testReconnectsAfterLinkDrop() async {
        makeManager()
        connectAndPair()

        radio.dropConnection(controller.id)
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testConnectsToRememberedDeviceOnLaunch() async {
        let id = UUID()
        makeManager(controllers: [FakeController(id: id)], remembered: id)
        XCTAssertEqual(manager.state, .connecting(id))
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testWaitsForBluetoothThenConnectsToRememberedDevice() async {
        let id = UUID()
        makeManager(controllers: [FakeController(id: id)], radioState: .poweredOff, remembered: id)
        XCTAssertEqual(manager.state, .poweredOff)

        radio.setRadioState(.poweredOn)
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testReconnectsAfterBluetoothIsToggled() async {
        makeManager()
        connectAndPair()

        radio.setRadioState(.poweredOff)
        scheduler.runUntilIdle()
        XCTAssertEqual(manager.state, .poweredOff)

        radio.setRadioState(.poweredOn)
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testStateRestorationAdoptsConnectedPeripheral() async {
        let id = UUID()
        makeManager(controllers: [FakeController(id: id)], radioState: .unknown, remembered: id)

        radio.restore([RestoredPeripheral(id: id, isConnected: true)])
        scheduler.runUntilIdle()
        radio.setRadioState(.poweredOn)
        scheduler.advance(by: 0.1)

        XCTAssertEqual(manager.state, .pairing(id), "should re-pair the restored link, not reconnect")
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testStateRestorationResumesPendingConnection() async {
        let id = UUID()
        makeManager(controllers: [FakeController(id: id, isPoweredOn: false)], radioState: .unknown)

        radio.restore([RestoredPeripheral(id: id, isConnected: false)])
        radio.setRadioState(.poweredOn)
        scheduler.runUntilIdle()
        XCTAssertEqual(manager.state, .connecting(id))

        radio.powerOn(id)
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testConnectFailuresRetryWithBackoff() async {
        makeManager(controllers: [FakeController(connectError: .other("Peer busy"))])
        manager.connect(to: controller.id)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(manager.state, .disconnected(.connectFailed("Peer busy"), willReconnect: true))
        XCTAssertEqual(scheduler.nextDelay ?? -1, 1, accuracy: 0.001)

        scheduler.advance(by: 1.1)
        XCTAssertEqual(scheduler.nextDelay ?? -1, 2, accuracy: 0.001)

        radio.update(controller.id) { $0.connectError = nil }
        scheduler.advance(by: 2.2)
        XCTAssertTrue(manager.state.isConnected)
    }

    func testReconnectPolicyCapsDelay() async {
        let policy = ReconnectPolicy(initialDelay: 1, multiplier: 2, maximumDelay: 30)
        XCTAssertEqual(policy.delay(forAttempt: 1), 1)
        XCTAssertEqual(policy.delay(forAttempt: 3), 4)
        XCTAssertEqual(policy.delay(forAttempt: 10), 30)
    }

    // MARK: User actions

    func testUserDisconnectDoesNotReconnect() async {
        makeManager()
        connectAndPair()

        manager.disconnect()
        scheduler.advance(by: 60)
        XCTAssertEqual(manager.state, .disconnected(.userRequested, willReconnect: false))
        XCTAssertTrue(radio.connectedPeripherals.isEmpty)
        XCTAssertTrue(radio.pendingConnections.isEmpty)

        manager.reconnect()
        scheduler.runUntilIdle()
        XCTAssertTrue(manager.state.isConnected)
    }

    func testForgetDeviceClearsRememberedDevice() async {
        makeManager()
        connectAndPair()

        manager.forgetDevice()
        scheduler.runUntilIdle()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(store.rememberedDeviceID)
        XCTAssertNil(manager.rememberedDeviceID)
    }

    func testSwitchingControllersDropsThePreviousOne() async {
        let first = FakeController(name: "First")
        let second = FakeController(name: "Second")
        makeManager(controllers: [first, second])
        manager.connect(to: first.id)
        scheduler.runUntilIdle()

        manager.connect(to: second.id)
        scheduler.runUntilIdle()
        XCTAssertEqual(radio.connectedPeripherals, [second.id])
        XCTAssertEqual(store.rememberedDeviceID, second.id)
    }

    // MARK: Writes and notifications

    func testWriteWithResponseReachesController() async throws {
        makeManager()
        connectAndPair()

        let payload = Data([0x01, 0x02, 0x03])
        let write = startWrite(payload)
        await waitForRadioWork()
        scheduler.runUntilIdle()
        try await write.value

        XCTAssertEqual(radio.receivedWrites.map(\.data), [payload])
        XCTAssertEqual(radio.receivedWrites.map(\.characteristic), [control])
    }

    func testWriteRejectedByControllerThrows() async {
        makeManager()
        connectAndPair()
        radio.writeHandler = { _, _ in .other("Write not permitted") }

        let write = startWrite(Data([0x01]))
        await waitForRadioWork()
        scheduler.runUntilIdle()
        do {
            try await write.value
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .writeFailed(.other("Write not permitted")))
        }
    }

    func testWriteOutsideCompanionServiceIsRefused() async {
        makeManager()
        connectAndPair()

        let foreign: GATTUUID = "00002A00-0000-1000-8000-00805F9B34FB"
        do {
            try await manager.write(Data([0xFF]), to: foreign)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .characteristicNotWritable(foreign))
        }
        XCTAssertTrue(radio.receivedWrites.isEmpty)
    }

    func testWriteWhenNotConnectedThrows() async {
        makeManager()
        do {
            try await manager.write(Data([0x01]), to: control)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .notConnected)
        }
    }

    func testOversizedWriteIsRejected() async {
        makeManager(controllers: [FakeController(maximumWriteLength: 20)])
        connectAndPair()
        do {
            try await manager.write(Data(count: 21), to: control)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .payloadTooLarge(size: 21, maximum: 20))
        }
    }

    func testPendingWriteFailsWhenLinkDrops() async {
        makeManager()
        connectAndPair()

        let write = startWrite(Data([0x01]))
        await waitForRadioWork()
        radio.powerOff(controller.id)
        scheduler.runUntilIdle()
        do {
            try await write.value
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .disconnected)
        }
    }

    func testPendingWriteFailsWhenSwitchingControllers() async {
        let first = FakeController(name: "First")
        let second = FakeController(name: "Second")
        makeManager(controllers: [first, second])
        connectAndPair()

        let write = startWrite(Data([0x01]))
        await waitForRadioWork()
        manager.connect(to: second.id)
        scheduler.runUntilIdle()
        do {
            try await write.value
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .disconnected)
        }
        XCTAssertTrue(manager.state.isConnected)
    }

    func testNotificationsAreForwarded() async throws {
        makeManager()
        connectAndPair()

        try await finishSelection(Task { try await manager.selectLiveNotifier(telemetry) })
        var received: [(GATTUUID, Data)] = []
        manager.onNotification = { received.append(($0, $1)) }
        radio.sendNotification(from: controller.id, characteristic: telemetry, data: Data([0xAA]))
        scheduler.runUntilIdle()

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, telemetry)
        XCTAssertEqual(received.first?.1, Data([0xAA]))
    }

    // MARK: Reads

    private let configStatus = CompanionGATT.configStatus

    private func startRead(_ characteristic: GATTUUID) -> Task<Data, Error> {
        let manager = manager!
        return Task { @MainActor in try await manager.read(characteristic) }
    }

    func testReadReturnsTheControllersValue() async throws {
        makeManager()
        connectAndPair()
        radio.readHandler = { _, characteristic in
            characteristic == CompanionGATT.configStatus ? .success(Data([0x00, 0x01])) : .failure(.att(0x02))
        }

        let read = startRead(configStatus)
        await waitForRadioWork()
        scheduler.runUntilIdle()
        let value = try await read.value
        XCTAssertEqual(value, Data([0x00, 0x01]))
    }

    func testReadErrorKeepsTheATTCode() async {
        makeManager()
        connectAndPair()
        radio.readHandler = { _, _ in .failure(.att(0x82)) }

        let read = startRead(configStatus)
        await waitForRadioWork()
        scheduler.runUntilIdle()
        do {
            _ = try await read.value
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .readFailed(.att(0x82)))
        }
    }

    func testReadOutsideCompanionServiceIsRefused() async {
        makeManager()
        connectAndPair()
        do {
            _ = try await manager.read(control)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .characteristicNotReadable(control))
        }
    }

    func testReadWhenNotConnectedThrows() async {
        makeManager()
        do {
            _ = try await manager.read(configStatus)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .notConnected)
        }
    }

    func testPendingReadFailsWhenLinkDrops() async {
        makeManager()
        connectAndPair()
        radio.readHandler = { _, _ in .success(Data([0x01])) }

        let read = startRead(configStatus)
        await waitForRadioWork()
        radio.powerOff(controller.id)
        scheduler.runUntilIdle()
        do {
            _ = try await read.value
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ConnectionError, .disconnected)
        }
    }

    // MARK: Observers

    func testStateObserverSeesEveryTransition() async {
        makeManager()
        var seen: [LinkState] = []
        let token = manager.observeState { seen.append($0) }
        connectAndPair()
        manager.disconnect()
        token.cancel()
        manager.reconnect()

        XCTAssertEqual(seen.count, 4, "\(seen)")
        XCTAssertEqual(seen.first, .connecting(controller.id))
        XCTAssertEqual(seen[1], .pairing(controller.id))
        XCTAssertTrue(seen[2].isConnected)
        XCTAssertEqual(seen.last, .disconnected(.userRequested, willReconnect: false))
    }

    func testNotificationObserversReceiveInOrderUntilCancelled() async throws {
        makeManager()
        connectAndPair()

        try await finishSelection(Task { try await manager.selectLiveNotifier(telemetry) })
        var received: [Data] = []
        let token = manager.observeNotifications { _, data in received.append(data) }
        radio.sendNotification(from: controller.id, characteristic: telemetry, data: Data([0x01]))
        radio.sendNotification(from: controller.id, characteristic: telemetry, data: Data([0x02]))
        scheduler.runUntilIdle()
        token.cancel()
        radio.sendNotification(from: controller.id, characteristic: telemetry, data: Data([0x03]))
        scheduler.runUntilIdle()

        XCTAssertEqual(received, [Data([0x01]), Data([0x02])])
    }
}
