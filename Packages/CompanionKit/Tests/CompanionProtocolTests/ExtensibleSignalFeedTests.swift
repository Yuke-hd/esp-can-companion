import Foundation
import XCTest
@testable import CompanionProtocol

final class ExtensibleSignalFeedTests: XCTestCase {
    private let start = ContinuousClock.now
    private func installed() throws -> (ExtensibleSignalFeed, ExtensibleFixtures) {
        let vectors = try ExtensibleFixtures.load()
        var feed = ExtensibleSignalFeed(); feed.install(catalog: vectors.catalog)
        return (feed, vectors)
    }
    private func packet(_ records: [UInt8] = [], sequence: UInt16 = 0) -> Data {
        Data([1, UInt8(truncatingIfNeeded: sequence), UInt8(sequence >> 8), 1, 0x78, 0x56, 0x34, 0x12] + records)
    }
    private func reading(_ feed: ExtensibleSignalFeed, _ key: String, _ seconds: Double = 0) -> SignalReading<ExtensibleSignalValue>? {
        feed.snapshot(at: start + .milliseconds(Int64(seconds * 1000))).reading(for: key)
    }
    func testCanonicalValuesAndEveryFailureVector() throws {
        var (feed, vectors) = try installed()
        XCTAssertNotNil(feed.receive(vectors.packet("typed_values"), at: start))
        XCTAssertEqual(reading(feed, "example.enabled")?.value, .boolean(true))
        XCTAssertEqual(reading(feed, "example.acceleration")?.value, .number(-12.5))
        XCTAssertEqual(reading(feed, "example.mode")?.value, .enumeration(choiceKey: "reverse"))
        XCTAssertNil(reading(feed, "example.future_type")?.value)
        for (name, key, handle) in [("nonfinite_number_clears_value", "example.acceleration", UInt16(2)),
                                  ("unknown_enum_choice_clears_value", "example.mode", 3),
                                  ("unknown_status_clears_value", "example.acceleration", 2)] {
            feed.receive(vectors.packet("typed_values"), at: start)
            feed.receive(vectors.packet(name), at: start + .seconds(1))
            XCTAssertEqual(reading(feed, key, 1), .unknown, name)
            XCTAssertEqual(feed.livenessDeadline(for: handle), start + .seconds(4), name)
        }
        feed.receive(vectors.packet("read_failure_without_value"), at: start)
        XCTAssertEqual(reading(feed, "example.enabled"), SignalReading(availability: .readFailed, value: nil))
        feed.receive(vectors.packet("opaque_unknown_type_exact_match_refreshes_liveness"), at: start)
        XCTAssertEqual(feed.livenessDeadline(for: 7), start + .seconds(3))
        XCTAssertEqual(reading(feed, "example.future_type"), .unknown)
    }
    func testUnknownTypeClearsImmediatelyWithoutRefreshingSignalClock() throws {
        var (feed, vectors) = try installed()
        feed.receive(vectors.packet("typed_values"), at: start)
        feed.receive(vectors.packet("mismatched_type_clears_without_liveness_refresh"), at: start + .seconds(1))
        XCTAssertEqual(reading(feed, "example.acceleration", 1), .unknown)
        XCTAssertEqual(feed.livenessDeadline(for: 2), start + .seconds(3))
        XCTAssertEqual(feed.stallDeadline, start + .seconds(3))
    }
    func testMalformedValidPrefixAndDuplicatesAdvanceNoStateOrClocks() throws {
        var (feed, vectors) = try installed()
        feed.receive(vectors.packet("typed_values"), at: start)
        for malformed in [packet([5, 1, 0, 1, 9, 0, 8, 2, 0, 2, 9]),
                          vectors.packet("duplicate_handle_rejects_entire_packet"),
                          vectors.packet("truncated_record_rejects_entire_packet"),
                          packet([4, 255, 255, 127, 0, 4, 255, 255, 127, 0])] {
            XCTAssertNil(feed.receive(malformed, at: start + .seconds(1)))
            XCTAssertEqual(reading(feed, "example.enabled", 1)?.value, .boolean(true))
            XCTAssertEqual(feed.stallDeadline, start + .seconds(2))
            XCTAssertEqual(feed.livenessDeadline(for: 1), start + .seconds(3))
        }
        var wrongFormat = packet(); wrongFormat[0] = 2
        XCTAssertNil(feed.receive(wrongFormat, at: start + .seconds(1)))
        XCTAssertEqual(feed.stallDeadline, start + .seconds(2))
    }
    func testIndependentExpirationAndStallBoundaries() throws {
        var (feed, vectors) = try installed()
        feed.receive(vectors.packet("typed_values"), at: start)
        feed.receive(packet([5, 1, 0, 1, 9, 0]), at: start + .seconds(1))
        feed.receive(packet(), at: start + .seconds(2))
        XCTAssertEqual(reading(feed, "example.acceleration", 2.999)?.availability, .fresh)
        XCTAssertEqual(reading(feed, "example.acceleration", 3), .unknown)
        XCTAssertEqual(reading(feed, "example.enabled", 3.999)?.value, .boolean(false))
        XCTAssertEqual(reading(feed, "example.enabled", 4), .unknown)
        XCTAssertTrue(feed.snapshot(at: start + .seconds(4)).isStalled)
    }
    func testStallFollowedByEmptyHeartbeatCannotResurrectReading() throws {
        var (feed, vectors) = try installed()
        feed.receive(vectors.packet("typed_values"), at: start)
        XCTAssertEqual(reading(feed, "example.enabled", 1.999)?.availability, .fresh)
        XCTAssertEqual(reading(feed, "example.enabled", 2), .unknown)
        feed.receive(packet(), at: start + .milliseconds(2100))
        XCTAssertFalse(feed.snapshot(at: start + .milliseconds(2100)).isStalled)
        XCTAssertEqual(reading(feed, "example.enabled", 2.1), .unknown)
        XCTAssertNotNil(feed.catalog)
        feed.receive(packet([5, 1, 0, 1, 9, 0]), at: start + .milliseconds(2200))
        XCTAssertEqual(reading(feed, "example.enabled", 2.2)?.value, .boolean(false))
        XCTAssertEqual(reading(feed, "example.acceleration", 2.2), .unknown)
    }
    func testTokenInvalidationSuspensionAndSameTokenReconnect() throws {
        var (feed, vectors) = try installed()
        feed.receive(vectors.packet("typed_values"), at: start)
        XCTAssertNil(feed.receive(vectors.packet("wrong_token_invalidates_mapping"), at: start))
        XCTAssertTrue(feed.snapshot(at: start).needsCatalog)
        XCTAssertTrue(feed.snapshot(at: start).signals.isEmpty)
        XCTAssertNil(feed.stallDeadline)
        XCTAssertNil(feed.receive(vectors.packet("typed_values"), at: start))
        feed.install(catalog: vectors.catalog)
        XCTAssertEqual(reading(feed, "example.enabled"), .unknown)
        feed.receive(vectors.packet("typed_values"), at: start)
        feed.reset(); feed.install(catalog: vectors.catalog)
        XCTAssertNil(feed.livenessDeadline(for: 1))
        XCTAssertEqual(reading(feed, "example.enabled"), .unknown)
        XCTAssertNotNil(feed.receive(vectors.packet("typed_values"), at: start))
    }
    func testUnknownHandleMixedWithKnownAndSequenceWrap() throws {
        var (feed, _) = try installed()
        XCTAssertNotNil(feed.receive(packet([4, 255, 255, 127, 0, 5, 1, 0, 1, 9, 1], sequence: 65535), at: start))
        XCTAssertEqual(reading(feed, "example.enabled")?.value, .boolean(true))
        XCTAssertEqual(feed.snapshot(at: start).sequence, 65535)
        feed.receive(packet(sequence: 0), at: start)
        XCTAssertEqual(feed.snapshot(at: start).sequence, 0)
        XCTAssertNil(feed.livenessDeadline(for: 65535))
    }
    func testSemanticErrorsClearRecognizedValuesAndRefreshLiveness() throws {
        let cases: [(UInt16, UInt8, UInt8, [UInt8])] = [
            (1, 1, 9, []), (1, 1, 9, [2]), (1, 1, 1, [1]), (1, 1, 0x19, [1]), (1, 1, 7, []),
            (2, 2, 9, [0, 0, 0]), (2, 2, 9, [0, 0, 128, 127]), (2, 2, 9, [0, 0, 128, 255]),
            (2, 2, 9, [0, 0, 192, 127]), (3, 3, 9, [0, 0]), (3, 3, 9, [99, 0]), (3, 3, 9, [1])]
        for (handle, type, status, bytes) in cases {
            var (feed, vectors) = try installed()
            feed.receive(vectors.packet("typed_values"), at: start)
            let record = [UInt8(bytes.count + 4), UInt8(handle), 0, type, status] + bytes
            feed.receive(packet(record), at: start + .seconds(1))
            let key = vectors.catalog.descriptor(for: handle)!.key
            XCTAssertEqual(reading(feed, key, 1), .unknown, "\(record)")
            XCTAssertEqual(feed.livenessDeadline(for: handle), start + .seconds(4))
        }
    }
    func testSignedZeroSubnormalRetainedStaleAndBrakePolicy() throws {
        var (feed, vectors) = try installed()
        for bits: UInt32 in [0x80000000, 1, 0x80000001] {
            var bytes = Data(); bytes.appendLittleEndian(bits)
            feed.receive(packet([8, 2, 0, 2, 10] + bytes), at: start)
            guard case .number(let number) = reading(feed, "example.acceleration")?.value else { return XCTFail("missing number") }
            XCTAssertEqual(number.bitPattern, bits)
            XCTAssertEqual(reading(feed, "example.acceleration")?.availability, .stale)
        }
        // Build a catalog entry for the narrowly scoped brake semantic key.
        let descriptor = vectors.catalog.descriptors[0]
        var body = Data(); body.appendLittleEndian(descriptor.handle)
        for (tag, value) in [(UInt8(1), Data("vehicle.brake_pressed".utf8)), (2, Data([1])), (3, Data("none".utf8)), (4, Data("reference".utf8))] {
            body.append(tag); body.appendLittleEndian(UInt16(value.count)); body.append(value)
        }
        var doc = Data([1, 1, 0]); doc.appendLittleEndian(UInt16(body.count)); doc.append(body)
        feed.install(catalog: try SignalCatalog(decoding: doc, token: vectors.catalog.token))
        feed.receive(packet([5, 1, 0, 1, 9, 1]), at: start)
        XCTAssertEqual(reading(feed, "vehicle.brake_pressed")?.availability, .freshnessUnverified)
        XCTAssertEqual(reading(feed, "vehicle.brake_pressed")?.value, .boolean(true))
    }
}
