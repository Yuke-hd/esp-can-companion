import XCTest
@testable import CompanionProtocol

final class CompanionProtocolTests: XCTestCase {
    func testSupportedVersionIsSet() {
        XCTAssertGreaterThan(CompanionProtocol.supportedVersion, 0)
    }
}
