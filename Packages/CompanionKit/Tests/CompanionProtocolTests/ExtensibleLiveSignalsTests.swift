import Foundation
import XCTest
@testable import CompanionProtocol

final class ExtensibleLiveSignalsTests: XCTestCase {
    func testFramingAndDuplicatesAreRejected() throws {
        for suffix: [UInt8] in [[0], [3, 1, 0, 1], [8, 1, 0, 1, 9],
                               [4, 1, 0, 1, 0, 4, 1, 0, 1, 0],
                               [4, 255, 255, 127, 0, 4, 255, 255, 127, 0]] {
            XCTAssertThrowsError(try ExtensibleLiveSignalPacket(decoding: packet(suffix)))
        }
        XCTAssertThrowsError(try ExtensibleLiveSignalPacket(decoding: Data(repeating: 0, count: 245)))
        XCTAssertThrowsError(try ExtensibleLiveSignalPacket(decoding: Data([1, 0])))
        var wrong = packet([]); wrong[0] = 2
        XCTAssertThrowsError(try ExtensibleLiveSignalPacket(decoding: wrong))
    }
    func testHeaderSequenceFlagsAndUnknownRecords() throws {
        var data = packet([6, 255, 255, 127, 249, 4, 5]); data[1] = 255; data[2] = 255; data[3] = 255
        let decoded = try ExtensibleLiveSignalPacket(decoding: data)
        XCTAssertEqual(decoded.sequence, 65535)
        XCTAssertTrue(decoded.isTelemetryStarted)
        XCTAssertEqual(decoded.token, 0x12345678)
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertEqual(decoded.records[0].value, Data([4, 5]))
        XCTAssertEqual(try ExtensibleLiveSignalPacket(decoding: packet([])).sequence, 0)
    }
    func testCanonicalTypedPacket() throws {
        let vectors = try ExtensibleFixtures.load()
        let decoded = try ExtensibleLiveSignalPacket(decoding: vectors.packet("typed_values"))
        XCTAssertEqual(decoded.records.map(\.handle), [1, 2, 3])
        XCTAssertEqual(decoded.records.map(\.type), [1, 2, 3])
    }
    private func packet(_ suffix: [UInt8]) -> Data { Data([1, 0, 0, 1, 0x78, 0x56, 0x34, 0x12] + suffix) }
}
struct ExtensibleFixtures {
    let catalog: SignalCatalog
    let packets: [String: Data]
    static func load() throws -> Self {
        let url = Bundle.module.url(forResource: "extensible-live-v1", withExtension: "json", subdirectory: "Fixtures/golden-vectors")!
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let document = root["catalog"] as! [String: Any]
        let catalog = try SignalCatalog(decoding: hex(document["document_hex"] as! String), token: 0x12345678)
        var packets: [String: Data] = [:]
        for row in root["notifications"] as! [[String: Any]] { packets[row["name"] as! String] = hex(row["packet_hex"] as! String) }
        return Self(catalog: catalog, packets: packets)
    }
    func packet(_ name: String) -> Data { packets[name]! }
    static func hex(_ value: String) -> Data {
        var result = Data(); var index = value.startIndex
        while index < value.endIndex { let end = value.index(index, offsetBy: 2); result.append(UInt8(value[index..<end], radix: 16)!); index = end }
        return result
    }
}
