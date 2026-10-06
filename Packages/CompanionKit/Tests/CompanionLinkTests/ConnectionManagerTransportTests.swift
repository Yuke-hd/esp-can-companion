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

    func testCancelledSubscriptionStopsDelivery() async {
        let bench = Bench()
        let transport = ConnectionManagerTransport(manager: bench.manager)
        await bench.connect()

        let events = LockedEvents()
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
