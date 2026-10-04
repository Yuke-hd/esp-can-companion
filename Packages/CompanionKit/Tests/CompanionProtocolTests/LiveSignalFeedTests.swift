import XCTest
@testable import CompanionProtocol

final class LiveSignalFeedTests: XCTestCase {
    private let start = ContinuousClock().now

    /// A frame with every signal at `nibble`, all Boolean bits set.
    private func frame(sequence: UInt8 = 0, nibble: UInt8) -> Data {
        var value = Data([1, sequence, 1, 0x10, 0x27, 0x00, 0x00, 1, 5, 5, 1, 0xFF, 0x1F])
        value.append(contentsOf: (0..<10).map { _ in nibble | nibble << 4 })
        return value
    }

    func testNoFrameYetIsAllUnknown() {
        let feed = LiveSignalFeed()
        XCTAssertTrue(feed.isStalled(at: start))
        XCTAssertEqual(feed.snapshot(at: start), .unknown)
    }

    func testStalledStreamShowsUnknownNotLastAvailability() {
        var feed = LiveSignalFeed()
        XCTAssertNotNil(feed.receive(frame(nibble: 0x09), at: start))
        XCTAssertEqual(feed.snapshot(at: start + .milliseconds(1999)).turnState.availability, .fresh)
        XCTAssertEqual(feed.snapshot(at: start + .seconds(2)), .unknown)
        XCTAssertEqual(feed.stallDeadline, start + .seconds(2))

        feed.receive(frame(sequence: 1, nibble: 0x09), at: start + .seconds(3))
        XCTAssertEqual(feed.snapshot(at: start + .seconds(3)).sequence, 1)
    }

    func testDiscardedFramesAreNotSignsOfLife() {
        var feed = LiveSignalFeed()
        feed.receive(frame(nibble: 0x09), at: start)
        XCTAssertNil(feed.receive(Data([2]) + Data(count: 22), at: start + .milliseconds(1500)))
        XCTAssertTrue(feed.isStalled(at: start + .seconds(2)))
    }

    /// Safety invariant: brake is never shown as fresh, whatever the frame says.
    func testBrakeIsNeverFresh() throws {
        for code: UInt8 in 0...7 {
            let decoded = try LiveSignalFrame(decoding: frame(nibble: code | 0x08))
            XCTAssertNotEqual(decoded.brakePressed.availability, .fresh, "code \(code)")
            XCTAssertFalse(decoded.brakePressed.isLive, "code \(code)")
            XCTAssertEqual(decoded.brakePressed.value, true, "The value is kept, only freshness is withheld")
        }
    }

    /// Only availability code 1 is fresh; nothing else is promoted.
    func testOnlyCodeOneIsFresh() throws {
        for code: UInt8 in 0...7 {
            let decoded = try LiveSignalFrame(decoding: frame(nibble: code | 0x08))
            let readings = GoldenVectorTests.readings(of: decoded).dropLast()
            for reading in readings {
                XCTAssertEqual(reading.availability == "fresh", code == 1, "\(reading.name), code \(code)")
            }
        }
    }

    func testValueOnlyWithPresentBit() throws {
        let decoded = try LiveSignalFrame(decoding: frame(nibble: 0x01))
        XCTAssertEqual(decoded.engineRPM, SignalReading(availability: .fresh, value: nil))
        XCTAssertFalse(decoded.engineRPM.isLive)
        let present = try LiveSignalFrame(decoding: frame(nibble: 0x09))
        XCTAssertEqual(present.engineRPM, SignalReading(availability: .fresh, value: 2500))
        XCTAssertEqual(present.selectorPosition.value, .known(.drive))
        XCTAssertEqual(present.actualGear.value, .known(.first))
    }
}
