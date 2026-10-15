import Foundation
import XCTest
import CompanionLink
import CompanionProtocol
@testable import CANCompanion

final class DiscoveredSignalsViewTests: XCTestCase {
    private func installedFeed() throws -> ExtensibleSignalFeed {
        func u16(_ value: Int) -> [UInt8] { [UInt8(value & 255), UInt8(value >> 8)] }
        var body: [UInt8] = [1, 0]
        for (tag, bytes) in [(1, Array("future.new_boolean".utf8)), (2, [UInt8(1)]),
                             (3, Array("none".utf8)), (4, Array("unfamiliar-evidence".utf8))] {
            body += [UInt8(tag)] + u16(bytes.count) + bytes
        }
        let catalog = try SignalCatalog(decoding: Data([1, 1, 0] + u16(body.count) + body), token: 1)
        var feed = ExtensibleSignalFeed()
        feed.install(catalog: catalog)
        return feed
    }

    func testDiscoveryAndUnavailableStatesRemainDistinct() {
        XCTAssertEqual(DiscoveredSignalsView.State.resolve(snapshot: nil, unavailableReason: nil), .loading)
        for reason: CompanionLiveTelemetryUnavailableReason in [.capabilityUnavailable, .missingEndpoints, .notifierEnded] {
            XCTAssertEqual(DiscoveredSignalsView.State.resolve(snapshot: nil, unavailableReason: reason), .unavailable)
        }
        XCTAssertEqual(DiscoveredSignalsView.State.resolve(snapshot: nil, unavailableReason: .connectionEnded), .disconnected)
    }

    func testNewCatalogKeyUpdatesThenClearsOnStallAndInvalidation() throws {
        var feed = try installedFeed()
        let start = ContinuousClock.now
        XCTAssertNotNil(feed.receive(Data([1, 0, 0, 1, 1, 0, 0, 0, 5, 1, 0, 1, 11, 1]), at: start))
        let live = feed.snapshot(at: start)
        XCTAssertEqual(DiscoveredSignalsView.State.resolve(snapshot: live, unavailableReason: nil), .ready)
        let rows = SignalReadout(snapshot: live).rows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].key, "future.new_boolean")
        XCTAssertEqual(rows[0].value, "True")
        XCTAssertEqual(rows[0].status, .unverified)
        XCTAssertEqual(rows[0].accessibilityText,
                       "future.new_boolean, Boolean, True, Unverified, Unit: none, Catalog evidence: unfamiliar-evidence")
        let stalled = feed.snapshot(at: start + .seconds(2))
        XCTAssertEqual(DiscoveredSignalsView.State.resolve(snapshot: stalled, unavailableReason: nil), .stalled)
        XCTAssertNil(SignalReadout(snapshot: stalled).rows[0].value)
        feed.reset()
        let invalidated = feed.snapshot(at: start)
        XCTAssertTrue(SignalReadout(snapshot: invalidated).rows.isEmpty)
        XCTAssertEqual(DiscoveredSignalsView.State.resolve(snapshot: invalidated, unavailableReason: nil), .loading)
    }

    func testValidatedEmptyCatalogGetsEmptyState() throws {
        var feed = ExtensibleSignalFeed()
        feed.install(catalog: try SignalCatalog(decoding: Data([1, 0, 0]), token: 1))
        let snapshot = feed.snapshot(at: .now)
        XCTAssertTrue(SignalReadout(snapshot: snapshot).rows.isEmpty)
        XCTAssertEqual(DiscoveredSignalsView.State.resolve(snapshot: snapshot, unavailableReason: nil), .empty)
    }
}
