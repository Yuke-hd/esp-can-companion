import XCTest
import BLETransport
import CompanionProtocol
@testable import CompanionLink

/// `ControllerSession` as the preset sync flow's link.
@MainActor
final class PresetSyncLinkTests: XCTestCase {
    /// Runs `body` while advancing the bench's virtual time, until it returns.
    private func run<T: Sendable>(
        _ bench: Bench,
        _ body: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let task = Task { try await body() }
        let done = LockedFlag()
        Task { _ = try? await task.value; done.set() }
        for _ in 0..<2_000 where !done.isSet {
            bench.scheduler.advance(by: 0.01)
            try await Task.sleep(for: .milliseconds(1))
        }
        return try await task.value
    }

    func testCurrentClientNeedsAReadySession() async throws {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        do {
            _ = try await session.currentClient()
            XCTFail("Expected no client while offline")
        } catch {
            XCTAssertEqual(error as? CompanionClientError, .transport(.notConnected))
        }

        await bench.connect()
        await bench.settle { session.phase == .ready }
        let client = try await session.currentClient()
        XCTAssertTrue(client === session.client)
        let info = await client.deviceInfo
        XCTAssertNotNil(info, "Device info is already read")
    }

    func testClientAfterRestartWaitsForTheControllerToComeBack() async throws {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }

        // The commit was accepted: the controller reports RestartPending,
        // then drops the link and restarts with the new config.
        bench.demo.state = .restartPending
        let id = bench.peripheral.id
        let client = try await run(bench) {
            async let waited = session.clientAfterRestart(timeout: .seconds(30), pollInterval: .milliseconds(1))
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertNotEqual(session.phase, .offline, "Still on the old link")
            bench.radio.powerOff(id)
            bench.demo.state = .idle
            bench.demo.activeSource = .persistedOverride
            bench.demo.activeDocument = DemoController.customDocument
            try await Task.sleep(for: .milliseconds(30))
            bench.radio.powerOn(id)
            return try await waited
        }

        XCTAssertTrue(client === session.client)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.configStatus?.activeSource, .known(.persistedOverride))
    }

    func testClientAfterRestartReturnsWhenNoRestartIsPending() async throws {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        await bench.connect()
        await bench.settle { session.phase == .ready }

        let client = try await run(bench) {
            try await session.clientAfterRestart(timeout: .seconds(30), pollInterval: .milliseconds(1))
        }
        XCTAssertTrue(client === session.client)
    }

    func testClientAfterRestartTimesOutWhileOffline() async throws {
        let bench = Bench()
        let session = ControllerSession(connection: bench.manager)
        do {
            _ = try await session.clientAfterRestart(timeout: .milliseconds(50), pollInterval: .milliseconds(5))
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? CompanionClientError, .timedOut(.readConfigStatus))
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
