import XCTest
import PresetSync
import CompanionLink
@testable import CANCompanion

@MainActor
final class AppModelSyncTests: XCTestCase {
    func testAppModelKeepsConfirmationInSharedSyncModel() throws {
        let app = AppModel(session: DemoScenario.connected.makeSession(latency: 0.001))
        let sync = try XCTUnwrap(app.presetSync)
        let preset = try XCTUnwrap(sync.presets.first)
        sync.requestPush(preset)
        XCTAssertTrue(app.presetSync === sync)
        XCTAssertEqual(sync.phase, .confirming(.preset(preset)))
    }

    func testDeferredBluetoothCreatesOneSharedSyncModel() {
        let app = AppModel(deferring: { DemoScenario.notPaired.makeSession() })
        XCTAssertNil(app.presetSync)
        app.allowBluetooth()
        let sync = app.presetSync
        app.allowBluetooth()
        XCTAssertNotNil(sync)
        XCTAssertTrue(app.presetSync === sync)
    }

    func testPreviousConfigIsUnverifiedWhileSessionReloadIsPending() async throws {
        let session = DemoScenario.connected.makeSession(latency: 0.001)
        let app = AppModel(session: session)
        for _ in 0..<400 where session.phase != .ready {
            try await Task.sleep(for: .milliseconds(5))
        }
        let sync = try XCTUnwrap(app.presetSync)
        await sync.refresh()
        XCTAssertTrue(app.hasCurrentPresetRead)
        session.reload()
        XCTAssertNotNil(sync.active, "The previous read is retained for the sync flow")
        XCTAssertFalse(app.hasCurrentPresetRead, "A pending reconnect read cannot confirm the previous config")
    }

    func testChangedConfigIsUnverifiedAfterReconnectUntilPresetReadMatches() async throws {
        let session = DemoScenario.connected.makeSession(latency: 0.001)
        let app = AppModel(session: session)
        for _ in 0..<400 where session.phase != .ready {
            try await Task.sleep(for: .milliseconds(5))
        }
        let sync = try XCTUnwrap(app.presetSync)
        await sync.refresh()
        let preset = try XCTUnwrap(sync.presets.first)
        _ = try await session.client.uploadConfig(preset.config)
        _ = try await session.clientAfterRestart()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(app.hasCurrentPresetRead, "The retained factory read does not match the current preset CRC")
        await sync.refresh()
        XCTAssertEqual(sync.active?.presetID, preset.id)
        XCTAssertTrue(app.hasCurrentPresetRead)
    }
}
