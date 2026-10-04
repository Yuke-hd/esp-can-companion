import XCTest
@testable import BLETransport

@MainActor
final class ConnectionManagerTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var controller: FakeController!
    private var radio: FakeRadio!
    private var store: InMemoryDeviceStore!
    private var manager: ConnectionManager!

    private let control = CompanionServiceConfiguration.placeholderControlCharacteristic
    private let telemetry = CompanionServiceConfiguration.placeholderTelemetryCharacteristic

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

    func testNotificationsAreForwarded() async {
        makeManager()
        connectAndPair()

        var received: [(GATTUUID, Data)] = []
        manager.onNotification = { received.append(($0, $1)) }
        radio.sendNotification(from: controller.id, characteristic: telemetry, data: Data([0xAA]))
        scheduler.runUntilIdle()

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, telemetry)
        XCTAssertEqual(received.first?.1, Data([0xAA]))
    }
}
