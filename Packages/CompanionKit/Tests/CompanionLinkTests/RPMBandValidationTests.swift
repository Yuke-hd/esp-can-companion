import XCTest
import CompanionProtocol
@testable import CompanionLink

final class RPMBandValidationTests: XCTestCase {
    private func band(_ from: Double, _ to: Double, redline: Double?) -> RPMBand {
        RPMBand(fill: .init(from: from, to: to), redline: redline)
    }

    func testDefaultBandIsValid() {
        XCTAssertNil(AppConfig.default.rpmBand.issue)
    }

    func testFillMustStartAtZeroOrMore() {
        XCTAssertNil(band(0, 6500, redline: nil).issue)
        XCTAssertEqual(band(-1, 6500, redline: nil).issue, .fillStartBelowZero)
        XCTAssertEqual(band(.nan, 6500, redline: nil).issue, .fillStartBelowZero)
    }

    func testFillMustEndAtTheMaximumOrBelow() {
        XCTAssertEqual(RPMBand.maximumRPM, 12_000)
        XCTAssertNil(band(0, 12_000, redline: 12_000).issue)
        XCTAssertEqual(band(0, 12_001, redline: nil).issue, .fillEndAboveMaximum)
        XCTAssertEqual(band(0, .infinity, redline: nil).issue, .fillEndAboveMaximum)
        XCTAssertEqual(band(0, .nan, redline: nil).issue, .fillEndAboveMaximum)
    }

    func testFillStartMustBeBelowItsEnd() {
        XCTAssertNil(band(4999, 5000, redline: nil).issue)
        XCTAssertEqual(band(5000, 5000, redline: nil).issue, .fillStartNotBelowEnd)
        XCTAssertEqual(band(5001, 5000, redline: nil).issue, .fillStartNotBelowEnd)
    }

    func testFillIsRequired() {
        XCTAssertEqual(RPMBand(fill: nil, redline: 6000).issue, .missingFill)
    }

    func testRedlineMayBeOff() {
        XCTAssertNil(band(1000, 6500, redline: nil).issue)
    }

    func testRedlineMustBeAboveTheFillStart() {
        XCTAssertNil(band(1000, 6500, redline: 1001).issue)
        XCTAssertEqual(band(1000, 6500, redline: 1000).issue, .redlineNotAboveFillStart)
        XCTAssertEqual(band(1000, 6500, redline: 0).issue, .redlineNotAboveFillStart)
        XCTAssertEqual(band(1000, 6500, redline: .nan).issue, .redlineNotAboveFillStart)
    }

    func testRedlineMustBeAtTheFillEndOrBelow() {
        XCTAssertNil(band(1000, 6500, redline: 6500).issue)
        XCTAssertEqual(band(1000, 6500, redline: 6501).issue, .redlineAboveFillEnd)
        XCTAssertEqual(band(1000, 6500, redline: .infinity).issue, .redlineAboveFillEnd)
    }

    func testFillRulesAreReportedBeforeRedlineRules() {
        XCTAssertEqual(band(-1, 6500, redline: 9000).issue, .fillStartBelowZero)
    }

    func testInvalidBandIsReplacedByTheDefaultBandOnly() {
        let invalid = AppConfig(rpmBand: band(7000, 6000, redline: 6500), brakePressureBarScale: 120)
        let valid = AppConfig(rpmBand: band(1000, 7000, redline: nil), brakePressureBarScale: 120)
        XCTAssertEqual(invalid.withValidRPMBand, AppConfig(rpmBand: AppConfig.default.rpmBand, brakePressureBarScale: 120))
        XCTAssertEqual(valid.withValidRPMBand, valid)
    }
}
