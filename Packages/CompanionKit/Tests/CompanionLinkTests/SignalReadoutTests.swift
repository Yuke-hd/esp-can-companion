import Foundation
import XCTest
@testable import CompanionProtocol
@testable import CompanionLink

final class SignalReadoutTests: XCTestCase {
    private func descriptor(_ key: String = "example.signal", type: WireValue<SignalType> = .known(.number),
                            choices: [SignalEnumChoice] = []) -> SignalDescriptor {
        SignalDescriptor(handle: 1, key: key, type: type, unit: "future-unit", evidence: "future-evidence", choices: choices)
    }
    private func row(_ value: ExtensibleSignalValue?, availability: SignalAvailability = .fresh,
                     descriptor: SignalDescriptor? = nil, stalled: Bool = false) -> SignalReadout.Row {
        SignalReadout.Row(state: ExtensibleSignalState(descriptor: descriptor ?? self.descriptor(),
            reading: SignalReading(availability: availability, value: value)), stalled: stalled)
    }
    func testTypedValuesAndDiscoveredChoicesAreNotHardCoded() {
        let boolean = row(.boolean(false), availability: .freshnessUnverified, descriptor: descriptor(type: .known(.boolean)))
        XCTAssertEqual(boolean.value, "False")
        XCTAssertEqual(boolean.status, .unverified)
        XCTAssertEqual(row(.number(-12.5)).value, "-12.5")
        let choices = [SignalEnumChoice(handle: 1, key: "new.choice"), SignalEnumChoice(handle: 2, key: "other.choice")]
        let enumeration = row(.enumeration(choiceKey: "new.choice"), descriptor: descriptor(type: .known(.enumeration), choices: choices))
        XCTAssertEqual(enumeration.value, "new.choice")
        XCTAssertEqual(enumeration.choices, ["new.choice", "other.choice"])
        XCTAssertTrue(enumeration.accessibilityText.contains("Choices: new.choice, other.choice"))
    }
    func testUnavailableStatusesAndStallNeverShowObsoleteValues() {
        for availability: SignalAvailability in [.stale, .noData, .unavailable, .readFailed, .notSupported, .unknown] {
            let readout = row(.number(123), availability: availability)
            XCTAssertNil(readout.value)
            XCTAssertTrue(readout.accessibilityText.contains("no value"))
            XCTAssertEqual(readout.status, PitWallReadout.Freshness(availability))
        }
        XCTAssertNil(row(.number(123), stalled: true).value)
        XCTAssertEqual(row(.number(123), stalled: true).status, .unknown)
    }
    func testOpaqueTypesAndMetadataAreConservative() {
        let opaque = row(.number(123), descriptor: descriptor(type: .unknown(127)))
        XCTAssertEqual(opaque.type, "Unsupported type (127)")
        XCTAssertEqual(opaque.status, .unknown)
        XCTAssertNil(opaque.value)
        XCTAssertEqual(opaque.unit, "future-unit")
        XCTAssertEqual(opaque.evidence, "future-evidence")
        XCTAssertTrue(opaque.accessibilityText.contains("Unit: future-unit"))
        XCTAssertTrue(opaque.accessibilityText.contains("Catalog evidence: future-evidence"))
        XCTAssertNil(row(.boolean(true)).value)
        XCTAssertNil(row(.number(.infinity)).value)
        XCTAssertNil(row(.enumeration(choiceKey: "absent"), descriptor: descriptor(type: .known(.enumeration))).value)
    }
    func testExactWireIdentityForCanonicallyEquivalentKeys() {
        let composed = row(.number(1), descriptor: descriptor("example.é"))
        let decomposed = row(.number(2), descriptor: descriptor("example.e\u{301}"))
        XCTAssertEqual(composed.key, decomposed.key)
        XCTAssertNotEqual(composed.id, decomposed.id)
        XCTAssertNotEqual(composed.accessibilityIdentifier, decomposed.accessibilityIdentifier)
        XCTAssertEqual(composed.accessibilityIdentifier, "signals.row.6578616d706c652ec3a9")
        let choices = [SignalEnumChoice(handle: 1, key: "é")]
        XCTAssertNil(row(.enumeration(choiceKey: "e\u{301}"), descriptor: descriptor(type: .known(.enumeration), choices: choices)).value)
    }
    func testCatalogOrderIsStableAndInvalidationClearsRows() throws {
        func u16(_ value: Int) -> [UInt8] { [UInt8(value & 255), UInt8(value >> 8)] }
        var document: [UInt8] = [1, 3, 0]
        for (index, key) in ["z.future", "a.é", "a.e\u{301}"].enumerated() {
            var body = u16(index + 1)
            for (tag, bytes) in [(1, Array(key.utf8)), (2, [UInt8(2)]), (3, Array("rpm".utf8)), (4, Array("reference".utf8))] {
                body += [UInt8(tag)] + u16(bytes.count) + bytes
            }
            document += u16(body.count) + body
        }
        var feed = ExtensibleSignalFeed()
        feed.install(catalog: try SignalCatalog(decoding: Data(document), token: 1))
        let start = ContinuousClock.now
        let first = SignalReadout(snapshot: feed.snapshot(at: start))
        XCTAssertEqual(first.rows.map(\.id), [Data("a.e\u{301}".utf8), Data("a.é".utf8), Data("z.future".utf8)])
        XCTAssertTrue(first.rows.allSatisfy { $0.value == nil })
        feed.reset()
        XCTAssertTrue(SignalReadout(snapshot: feed.snapshot(at: start)).rows.isEmpty)
        XCTAssertTrue(SignalReadout(snapshot: nil).rows.isEmpty)
    }
}
