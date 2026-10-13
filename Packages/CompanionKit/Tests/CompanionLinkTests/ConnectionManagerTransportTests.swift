import XCTest
import BLETransport
import CompanionProtocol
@testable import CompanionLink

@MainActor
final class ConnectionManagerTransportTests: XCTestCase {
    private func expectError(
        _ expected: CompanionTransportError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: @escaping () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CompanionTransportError, expected, file: file, line: line)
        }
    }

    /// BLETransport cannot depend on CompanionProtocol, so the transport's copy of
    /// the decodable layouts must be kept in step with the protocol's by hand.
    func testTransportAcceptsExactlyTheLayoutsTheProtocolDecodes() {
        XCTAssertEqual(
            CompanionServiceConfiguration.protocolV1.supportedLiveSignalLayouts,
            CompanionProtocol.supportedLiveSignalLayouts
        )
    }

    func testOptionalEndpointRolesAndPermissions() {
        XCTAssertEqual(ConnectionManagerTransport.gattUUID(for: .signalCatalog), GATTUUID("AB490006-09B6-4509-BF8E-2790253BAF98"))
        XCTAssertEqual(ConnectionManagerTransport.gattUUID(for: .extensibleLiveSignals), GATTUUID("AB490007-09B6-4509-BF8E-2790253BAF98"))
        for role in CompanionCharacteristic.allCases {
            XCTAssertEqual(ConnectionManagerTransport.characteristic(for: ConnectionManagerTransport.gattUUID(for: role)), role)
        }
        XCTAssertNil(ConnectionManagerTransport.characteristic(for: "AB490008-09B6-4509-BF8E-2790253BAF98"))
        let configuration = CompanionServiceConfiguration.protocolV1
        XCTAssertTrue(configuration.readableCharacteristicUUIDs.contains(CompanionGATT.signalCatalog))
        XCTAssertTrue(configuration.writableCharacteristicUUIDs.contains(CompanionGATT.signalCatalog))
        XCTAssertFalse(configuration.readableCharacteristicUUIDs.contains(CompanionGATT.extensibleLiveSignals))
        XCTAssertFalse(configuration.writableCharacteristicUUIDs.contains(CompanionGATT.extensibleLiveSignals))
        // Merely exposing the role must not choose a telemetry subscription.
        XCTAssertEqual(configuration.notifyingCharacteristicUUIDs, [CompanionGATT.configStatus, CompanionGATT.liveSignals])
        XCTAssertEqual(configuration.pairingCharacteristicUUID, CompanionGATT.configStatus)
    }

    func testCatalogSelectorAndReadUseOnlyTheCatalogEndpoint() async throws {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()
        let selector = Data([1, 0x78, 0x56, 0x34, 0x12, 200, 0])
        let page = Data([1, 0x78, 0x56, 0x34, 0x12, 201, 0, 200, 0, 1, 0, 0xAA])
        let reads = LockedEvents()
        bench.radio.readHandler = { _, uuid in
            reads.append(uuid.string)
            return uuid == CompanionGATT.signalCatalog ? .success(page) : .failure(.characteristicNotFound(uuid))
        }
        bench.radio.writeHandler = { uuid, value in
            uuid == CompanionGATT.signalCatalog && value == selector ? nil : .other("Unexpected endpoint")
        }
        let write = Task { try await transport.write(selector, to: .signalCatalog) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        try await write.value
        let read = Task { try await transport.read(.signalCatalog) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        let value = try await read.value
        XCTAssertEqual(value, page)
        XCTAssertEqual(reads.values, [CompanionGATT.signalCatalog.string])
        XCTAssertEqual(bench.radio.receivedWrites.map(\.characteristic), [CompanionGATT.signalCatalog])
        XCTAssertEqual(bench.radio.receivedWrites.map(\.data), [selector])
    }

    func testMissingCatalogKeepsConnectionAndConfigurationUsable() async throws {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()
        // The existing demo has neither extension endpoint.
        let read = Task { try await transport.read(.signalCatalog) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        do {
            _ = try await read.value
            XCTFail("expected missing optional endpoint to fail")
        } catch CompanionTransportError.other { }
        let selector = Task { try await transport.write(Data([1, 0, 0, 0, 0, 0, 0]), to: .signalCatalog) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        await expectError(.att(.unknown(0x03))) { try await selector.value }
        XCTAssertTrue(bench.manager.state.isConnected)
        let write = Task { try await transport.write(ConfigWritePDU.abort.encoded, to: .config) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        try await write.value
        XCTAssertEqual(bench.radio.receivedWrites.map(\.characteristic), [CompanionGATT.config])
    }

    func testExtensibleNotificationsRouteWithoutLegacyOrUnknownDelivery() async throws {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()
        let events = LockedEvents()
        let activation = Task { try await transport.activateLiveNotifier(.extensibleLiveSignals) }
        await bench.settle { bench.manager.selectedLiveNotifier == CompanionGATT.extensibleLiveSignals }
        let lease = try await activation.value
        defer { lease.cancel() }
        let subscription = transport.subscribe(to: .extensibleLiveSignals) { data in events.append(data.base64EncodedString()) }
        let packet = Data([1, 0, 0, 1, 0x78, 0x56, 0x34, 0x12])
        bench.radio.sendNotification(from: bench.peripheral.id, characteristic: CompanionGATT.liveSignals, data: packet)
        bench.radio.sendNotification(from: bench.peripheral.id, characteristic: "AB490008-09B6-4509-BF8E-2790253BAF98", data: packet)
        bench.radio.sendNotification(from: bench.peripheral.id, characteristic: CompanionGATT.extensibleLiveSignals, data: packet)
        bench.scheduler.runUntilIdle()
        subscription.cancel()
        bench.radio.sendNotification(from: bench.peripheral.id, characteristic: CompanionGATT.extensibleLiveSignals, data: packet)
        bench.scheduler.runUntilIdle()
        XCTAssertEqual(events.values, [packet.base64EncodedString()])
    }

    func testActivationLeaseIsGenerationScopedAndReportsTerminationOnce() async throws {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()
        let endpoints = try await transport.availableCharacteristics()
        XCTAssertTrue(endpoints.contains(.signalCatalog))
        XCTAssertTrue(endpoints.contains(.extensibleLiveSignals))
        let first = Task { try await transport.activateLiveNotifier(.liveSignals) }
        await bench.settle { bench.manager.selectedLiveNotifier == CompanionGATT.liveSignals }
        let oldLease = try await first.value
        let oldGeneration = try XCTUnwrap(bench.manager.selectedLiveNotifierID)
        let events = LockedEvents()
        oldLease.onTermination { events.append("old ended") }
        let second = Task { try await transport.activateLiveNotifier(.extensibleLiveSignals) }
        await bench.settle { bench.manager.selectedLiveNotifier == CompanionGATT.extensibleLiveSignals }
        let newLease = try await second.value
        oldLease.cancel()
        try await bench.manager.clearLiveNotifier(ifSelectionID: oldGeneration)
        for _ in 0..<20 { await Task.yield(); bench.scheduler.runUntilIdle() }
        XCTAssertEqual(bench.manager.selectedLiveNotifier, CompanionGATT.extensibleLiveSignals)
        XCTAssertEqual(events.values, ["old ended"])
        newLease.onTermination { events.append("new ended") }
        bench.radio.onEvent?(.liveNotifierStopped(bench.peripheral.id, CompanionGATT.extensibleLiveSignals, .att(5)))
        newLease.cancel()
        XCTAssertEqual(events.values, ["old ended", "new ended"])
        newLease.onTermination { events.append("late registration") }
        XCTAssertEqual(events.values.last, "late registration")
        XCTAssertNil(bench.manager.selectedLiveNotifier)
    }

    func testDisconnectEndsActivationLeaseAndClearsEndpointMetadata() async throws {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()
        let activation = Task { try await transport.activateLiveNotifier(.liveSignals) }
        await bench.settle { bench.manager.selectedLiveNotifier == CompanionGATT.liveSignals }
        let lease = try await activation.value
        let events = LockedEvents()
        lease.onTermination { events.append("ended") }
        bench.manager.disconnect()
        XCTAssertEqual(events.values, ["ended"])
        XCTAssertTrue(bench.manager.availableCharacteristics.isEmpty)
        lease.cancel()
        XCTAssertEqual(events.values, ["ended"])
    }

    func testLegacyClientAwaitsActivationAndPropagatesFailure() async throws {
        let bench = Bench()
        let client = CompanionClient(transport: ConnectionManagerTransport(manager: bench.manager))
        await bench.connect()
        let info = Task { try await client.readDeviceInfo() }
        await bench.settle { bench.scheduler.nextDelay != nil }
        for _ in 0..<100 { bench.scheduler.runUntilIdle(); await Task.yield() }
        _ = try await info.value
        bench.radio.notificationHandler = { _, enabled in enabled ? .att(5) : nil }
        let stream = Task { try await client.liveSignals() }
        await bench.settle { bench.radio.notificationRequests.contains { $0.enabled } }
        for _ in 0..<100 { bench.scheduler.runUntilIdle(); await Task.yield() }
        do { _ = try await stream.value; XCTFail("expected CCCD failure") }
        catch { XCTAssertEqual(error as? CompanionClientError, .transport(.att(.known(.insufficientAuthentication)))) }
        XCTAssertNil(bench.manager.selectedLiveNotifier)
    }

    func testNotConnected() async {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await expectError(.notConnected) { _ = try await transport.read(.deviceInfo) }
        await expectError(.notConnected) { try await transport.write(Data([0x04]), to: .config) }
        await expectError(.notConnected) { _ = try await transport.maximumWriteLength() }
    }

    func testReadsAndWritesReachTheController() async throws {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()

        let read = Task { try await transport.read(.deviceInfo) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        let value = try await read.value
        XCTAssertEqual(try DeviceInfo(decoding: value), bench.demo.deviceInfo)

        let write = Task { try await transport.write(ConfigWritePDU.abort.encoded, to: .config) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        try await write.value
        XCTAssertEqual(bench.radio.receivedWrites.map(\.data), [ConfigWritePDU.abort.encoded])

        let maximum = try await transport.maximumWriteLength()
        XCTAssertEqual(maximum, bench.peripheral.maximumWriteLength)
    }

    func testATTErrorKeepsTheControllerCode() async {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()
        bench.radio.writeHandler = { _, _ in .att(ATTErrorCode.busy.rawValue) }

        let write = Task { try await transport.write(Data([0x01]), to: .command) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        await expectError(.att(.known(.busy))) { try await write.value }
    }

    func testOtherRadioErrorIsNotAControllerAnswer() async {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()
        bench.radio.writeHandler = { _, _ in .other("Unlikely error") }

        let write = Task { try await transport.write(Data([0x03]), to: .config) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        do {
            try await write.value
            XCTFail("expected a failure")
        } catch CompanionTransportError.other {
        } catch {
            XCTFail("expected .other, got \(error)")
        }
    }

    func testLinkDropDuringWriteIsDisconnected() async {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()

        let write = Task { try await transport.write(ConfigWritePDU.commit.encoded, to: .config) }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.radio.powerOff(bench.peripheral.id)
        bench.scheduler.runUntilIdle()
        await expectError(.disconnected) { try await write.value }
    }

    func testNotificationArrivesBeforeTheWriteResponse() async throws {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()

        let events = LockedEvents()
        let subscription = transport.subscribe(to: .configStatus) { _ in events.append("notification") }
        defer { subscription.cancel() }
        let radio = bench.radio
        let id = bench.peripheral.id
        radio.writeHandler = { characteristic, _ in
            radio.sendNotification(from: id, characteristic: CompanionGATT.configStatus, data: Data([1]), immediately: true)
            return nil
        }

        let write = Task {
            try await transport.write(ConfigWritePDU.abort.encoded, to: .config)
            events.append("response")
        }
        await bench.settle { bench.scheduler.nextDelay != nil }
        bench.scheduler.runUntilIdle()
        try await write.value
        XCTAssertEqual(events.values, ["notification", "response"])
    }

    func testCancelledSubscriptionStopsDelivery() async throws {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()

        let events = LockedEvents()
        let activation = Task { try await transport.activateLiveNotifier(.liveSignals) }
        await bench.settle { bench.manager.selectedLiveNotifier == CompanionGATT.liveSignals }
        let lease = try await activation.value
        defer { lease.cancel() }
        let subscription = transport.subscribe(to: .liveSignals) { _ in events.append("frame") }
        bench.radio.sendNotification(from: bench.peripheral.id, characteristic: CompanionGATT.liveSignals, data: Data([1]))
        bench.radio.sendNotification(from: bench.peripheral.id, characteristic: CompanionGATT.configStatus, data: Data([1]))
        bench.scheduler.runUntilIdle()
        subscription.cancel()
        bench.radio.sendNotification(from: bench.peripheral.id, characteristic: CompanionGATT.liveSignals, data: Data([2]))
        bench.scheduler.runUntilIdle()
        XCTAssertEqual(events.values, ["frame"])
    }
}

final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
