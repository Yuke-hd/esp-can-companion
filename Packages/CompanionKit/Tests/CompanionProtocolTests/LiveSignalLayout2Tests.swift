import XCTest
@testable import CompanionProtocol

final class LiveSignalLayout2Tests: XCTestCase {
    /// A layout 2 frame (28 bytes). Status nibble 19 is longitudinal, 20 is lateral.
    private func frame(
        version: UInt8 = 2,
        longitudinal: Int16 = 0,
        lateral: Int16 = 0,
        longitudinalNibble: UInt8 = 0x09,
        lateralNibble: UInt8 = 0x09
    ) -> Data {
        var value = Data([version, 0, 1, 0x10, 0x27, 0, 0, 1, 5, 5, 1, 0xFF, 0x1F])
        value.append(contentsOf: [UInt8](repeating: 0x11, count: 9))
        value.append(longitudinalNibble << 4 | 0x01)
        value.append(lateralNibble)
        value.appendLittleEndian(UInt16(bitPattern: longitudinal))
        value.appendLittleEndian(UInt16(bitPattern: lateral))
        return value
    }

    private func assertRejects(
        _ value: Data,
        layoutVersion: UInt8,
        with expected: ProtocolDecodingError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try LiveSignalFrame(decoding: value, layoutVersion: layoutVersion), file: file, line: line) {
            XCTAssertEqual($0 as? ProtocolDecodingError, expected, file: file, line: line)
        }
    }

    // MARK: Values

    func testLongitudinalIsSignedInHundredthsOfMetresPerSecondSquared() throws {
        let expected: [(raw: Int16, value: Double)] = [
            (-32768, -327.68), (-1, -0.01), (0, 0), (32767, 327.67),
        ]
        for (raw, value) in expected {
            let decoded = try LiveSignalFrame(decoding: frame(longitudinal: raw), layoutVersion: 2)
            XCTAssertEqual(decoded.longitudinalAcceleration.value ?? .nan, value, accuracy: 1e-9, "raw \(raw)")
            XCTAssertEqual(decoded.lateralAcceleration.value, 0, "The other axis is untouched")
        }
    }

    func testLateralIsSignedInThousandthsOfMetresPerSecondSquared() throws {
        let expected: [(raw: Int16, value: Double)] = [
            (-32768, -32.768), (-1, -0.001), (0, 0), (32767, 32.767),
        ]
        for (raw, value) in expected {
            let decoded = try LiveSignalFrame(decoding: frame(lateral: raw), layoutVersion: 2)
            XCTAssertEqual(decoded.lateralAcceleration.value ?? .nan, value, accuracy: 1e-9, "raw \(raw)")
            XCTAssertEqual(decoded.longitudinalAcceleration.value, 0, "The other axis is untouched")
        }
    }

    func testEachAxisHasItsOwnAvailabilityAndValuePresence() throws {
        let decoded = try LiveSignalFrame(
            decoding: frame(longitudinal: 250, lateral: -400, longitudinalNibble: 0x01, lateralNibble: 0x0A),
            layoutVersion: 2
        )
        XCTAssertEqual(decoded.longitudinalAcceleration, SignalReading(availability: .fresh, value: nil))
        XCTAssertEqual(decoded.lateralAcceleration, SignalReading(availability: .stale, value: -0.4))
        XCTAssertFalse(decoded.longitudinalAcceleration.isLive)
        XCTAssertFalse(decoded.lateralAcceleration.isLive)

        let live = try LiveSignalFrame(decoding: frame(longitudinal: 250, lateral: -400), layoutVersion: 2)
        XCTAssertTrue(live.longitudinalAcceleration.isLive)
        XCTAssertTrue(live.lateralAcceleration.isLive)
    }

    func testLayout2KeepsEveryLayout1SignalInPlace() throws {
        let decoded = try LiveSignalFrame(decoding: frame(), layoutVersion: 2)
        XCTAssertEqual(decoded.engineRPM, SignalReading(availability: .fresh, value: nil))
        XCTAssertEqual(decoded.turnState.availability, .fresh)
        XCTAssertEqual(decoded.brakePressed.availability, .unknown, "Brake is still never fresh")
        XCTAssertTrue(decoded.isTelemetryStarted)
    }

    func testLayout1FramesHaveNoAcceleration() throws {
        let v1 = Data([1, 0, 1]) + Data(count: 20)
        let decoded = try LiveSignalFrame(decoding: v1)
        XCTAssertEqual(decoded.longitudinalAcceleration, .unknown)
        XCTAssertEqual(decoded.lateralAcceleration, .unknown)
        XCTAssertEqual(LiveSignalFrame.unknown.longitudinalAcceleration, .unknown)
    }

    // MARK: Golden vectors (hand-authored from the layout 2 wire doc)

    func testGoldenVectorBothAxesFresh() throws {
        // header | status: nibbles 0-18 fresh/no value, 19 and 20 fresh with value | +2.91 m/s², -1.500 m/s²
        let hex = "0205011027000001050501ff1f" + "111111111111111111" + "9109" + "2301" + "24fa"
        let decoded = try LiveSignalFrame(decoding: Self.bytes(hex), layoutVersion: 2)
        XCTAssertEqual(decoded.longitudinalAcceleration, SignalReading(availability: .fresh, value: 2.91))
        XCTAssertEqual(decoded.lateralAcceleration, SignalReading(availability: .fresh, value: -1.5))
        XCTAssertEqual(decoded.sequence, 5)
    }

    func testGoldenVectorUnverifiedLongitudinalAndStaleLateral() throws {
        // nibble 19 = freshness unverified without a value; nibble 20 = stale with a value (+1.000).
        let hex = "0205011027000001050501ff1f" + "111111111111111111" + "310a" + "0000" + "e803"
        let decoded = try LiveSignalFrame(decoding: Self.bytes(hex), layoutVersion: 2)
        XCTAssertEqual(decoded.longitudinalAcceleration, SignalReading(availability: .freshnessUnverified, value: nil))
        XCTAssertEqual(decoded.lateralAcceleration, SignalReading(availability: .stale, value: 1.0))
    }

    // MARK: Length and version are exact

    func testLayout2RequiresExactly28Bytes() throws {
        let valid = frame()
        XCTAssertEqual(valid.count, 28)
        XCTAssertNoThrow(try LiveSignalFrame(decoding: valid, layoutVersion: 2))
        XCTAssertThrowsError(try LiveSignalFrame(decoding: valid.dropLast(), layoutVersion: 2)) {
            XCTAssertEqual($0 as? ProtocolDecodingError, .truncated(field: "frame"))
        }
        XCTAssertThrowsError(try LiveSignalFrame(decoding: valid + [0], layoutVersion: 2)) {
            XCTAssertEqual($0 as? ProtocolDecodingError, .invalidValue(field: "frame"))
        }
    }

    func testLayout1StillRequiresExactly23Bytes() throws {
        let valid = Data([1, 0, 1]) + Data(count: 20)
        XCTAssertNoThrow(try LiveSignalFrame(decoding: valid, layoutVersion: 1))
        assertRejects(valid.dropLast(), layoutVersion: 1, with: .truncated(field: "frame"))
        assertRejects(valid + [0], layoutVersion: 1, with: .invalidValue(field: "frame"))
    }

    func testAFrameNeverDecodesAsTheOtherLayout() {
        let v1 = Data([1, 0, 1]) + Data(count: 20)
        let v2 = frame()
        assertRejects(v2, layoutVersion: 1, with: .invalidValue(field: "layout_version"))
        assertRejects(v1, layoutVersion: 2, with: .invalidValue(field: "layout_version"))
        // A frame whose version byte disagrees with its length is rejected either way:
        // the version byte is checked first, then the exact length.
        assertRejects(frame(version: 1), layoutVersion: 1, with: .invalidValue(field: "frame"))
        assertRejects(frame(version: 1), layoutVersion: 2, with: .invalidValue(field: "layout_version"))
        assertRejects(Data([2]) + v1.dropFirst(), layoutVersion: 2, with: .truncated(field: "frame"))
        assertRejects(Data([2]) + v1.dropFirst(), layoutVersion: 1, with: .invalidValue(field: "layout_version"))
        // The version-less decoder is layout 1.
        XCTAssertNoThrow(try LiveSignalFrame(decoding: v1))
        XCTAssertThrowsError(try LiveSignalFrame(decoding: v2)) {
            XCTAssertEqual($0 as? ProtocolDecodingError, .invalidValue(field: "layout_version"))
        }
    }

    func testUnknownLayoutVersionsAreRejected() {
        for version: UInt8 in [0, 3, 255] {
            assertRejects(frame(version: version), layoutVersion: version, with: .invalidValue(field: "layout_version"))
        }
    }

    // MARK: Feed

    func testFeedDecodesOnlyItsConfiguredLayout() {
        let start = ContinuousClock().now
        var v2Feed = LiveSignalFeed(layoutVersion: 2)
        XCTAssertNil(v2Feed.receive(Data([1, 0, 1]) + Data(count: 20), at: start))
        XCTAssertNotNil(v2Feed.receive(frame(longitudinal: 100), at: start))
        XCTAssertEqual(v2Feed.snapshot(at: start).longitudinalAcceleration.value, 1.0)

        var v1Feed = LiveSignalFeed()
        XCTAssertNil(v1Feed.receive(frame(), at: start))
    }

    private static func bytes(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }
}
