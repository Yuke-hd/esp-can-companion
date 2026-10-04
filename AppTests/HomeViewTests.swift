import XCTest
import BLETransport
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
}
