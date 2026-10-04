import XCTest
import BLETransport
import CompanionProtocol
import CompanionLink
@testable import CANCompanion

final class HomeViewTests: XCTestCase {
    private let id = UUID()

    private var allStates: [LinkState] {
        [
            .unknown, .unsupported, .unauthorized, .poweredOff, .idle, .scanning,
            .connecting(id), .pairing(id),
            .connected(ConnectedDevice(id: id, name: "Bench Controller", maximumWriteLength: 182)),
            .disconnected(.connectionLost(nil), willReconnect: true),
            .disconnected(.pairingFailed(nil), willReconnect: false),
            .disconnected(.bondRemoved, willReconnect: false),
            .disconnected(.unsupportedProtocol(major: 2), willReconnect: false),
        ]
    }

    func testEveryLinkStateHasATitleAndDetail() {
        for state in allStates {
            XCTAssertFalse(state.title.isEmpty)
            XCTAssertFalse(state.detail.isEmpty)
        }
    }

    func testConnectedShowsLive() {
        let state = LinkState.connected(ConnectedDevice(id: id, name: nil, maximumWriteLength: 20))
        XCTAssertEqual(state.pillStatus, .live)
    }

    func testRelinkingIsPendingNotAlert() {
        XCTAssertEqual(LinkState.disconnected(.connectionLost(nil), willReconnect: true).pillStatus, .pending)
        XCTAssertEqual(LinkState.disconnected(.pairingFailed(nil), willReconnect: false).pillStatus, .alert)
    }

    func testIncompatibleControllerIsNamed() {
        let state = LinkState.disconnected(.unsupportedProtocol(major: 2), willReconnect: false)
        XCTAssertEqual(state.title, "Incompatible")
        XCTAssertTrue(state.detail.contains("version 2"))
        XCTAssertEqual(state.pillStatus, .alert)
    }

    func testConfigSourceTitles() {
        XCTAssertEqual(ConfigSource.known(.factory).title, "Factory default")
        XCTAssertEqual(ConfigSource.known(.persistedOverride).title, "Custom override")
        XCTAssertEqual(ConfigSource.known(.none).title, "None")
        XCTAssertEqual(ConfigSource.unknown(7).title, "Unknown (7)")
    }

    func testBootWarnings() throws {
        var value = Data(count: ConfigStatus.minimumLength)
        value[2] = 0b1001 // override invalid, lighting setup failed
        let status = try ConfigStatus(decoding: value)
        XCTAssertEqual(status.bootWarnings.count, 2)
        XCTAssertTrue(status.bootWarnings[0].contains("LEDs are off"))

        let clean = try ConfigStatus(decoding: Data(count: ConfigStatus.minimumLength))
        XCTAssertEqual(clean.bootWarnings, [])
    }

    func testControllerCardMessages() {
        XCTAssertNotNil(ControllerSession.Phase.offline.message(for: .idle))
        XCTAssertTrue(ControllerSession.Phase.offline
            .message(for: .disconnected(.unsupportedProtocol(major: 3), willReconnect: false))?
            .contains("3") == true)
        XCTAssertNotNil(ControllerSession.Phase.loading.message(for: .idle))
        XCTAssertEqual(ControllerSession.Phase.failed("Nope.").message(for: .idle), "Nope.")
        XCTAssertNil(ControllerSession.Phase.ready.message(for: .idle))
    }

    func testActionRowHasOneVoiceOverLabel() throws {
        let config = try ControllerConfig(canonicalJSON: DemoController.factoryDocument)
        let brake = try XCTUnwrap(ConfigSummary(config).actions.first { $0.name == "brake" })
        XCTAssertEqual(brake.accessibilityText, "Brake. When brake pressed is on. Output: Lights LEDs 35–64")
    }

    @MainActor
    func testFirstLaunchDefersTheSessionUntilAllowed() {
        var created = 0
        let model = AppModel(deferring: {
            created += 1
            return DemoScenario.notPaired.makeSession()
        })
        XCTAssertTrue(model.needsBluetoothPermission)
        XCTAssertEqual(created, 0)

        model.allowBluetooth()
        model.allowBluetooth()
        XCTAssertFalse(model.needsBluetoothPermission)
        XCTAssertEqual(created, 1)
    }

    @MainActor
    func testHomeWorksEndToEndAgainstTheFakeDevice() async throws {
        let session = DemoScenario.notPaired.makeSession(latency: 0.001)
        let connection = session.connection
        try await waitUntil { connection.state == .idle }

        connection.startScan()
        try await waitUntil { !connection.discoveredDevices.isEmpty }
        connection.connect(to: connection.discoveredDevices[0].id)
        try await waitUntil { session.phase == .ready }

        XCTAssertEqual(session.deviceInfo?.protocolText, "v1.0")
        XCTAssertEqual(session.configStatus?.activeSource.title, "Factory default")
        guard case .summary(let summary)? = session.activeConfig else { return XCTFail("expected a summary") }
        XCTAssertEqual(summary.actions.count, 6)
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("condition never held")
    }
}
