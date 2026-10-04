import XCTest
import BLETransport
@testable import CANCompanion

final class HomeViewTests: XCTestCase {
    func testEveryLinkStateHasATitle() {
        let states: [LinkState] = [.idle, .scanning, .connecting, .connected, .disconnected(reason: nil)]
        for state in states {
            XCTAssertFalse(state.title.isEmpty)
        }
    }

    func testConnectedShowsSuccess() {
        XCTAssertEqual(LinkState.connected.pillStatus, .success)
    }
}
