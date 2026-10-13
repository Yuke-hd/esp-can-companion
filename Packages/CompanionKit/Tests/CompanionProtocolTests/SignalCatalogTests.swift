import Foundation
import XCTest
@testable import CompanionProtocol

final class SignalCatalogTests: XCTestCase {
    func testEmptyCatalogAndInvalidHeaders() throws {
        let catalog = try SignalCatalog(decoding: Data([1, 0, 0]), token: 1)
        XCTAssertTrue(catalog.descriptors.isEmpty)
        XCTAssertNil(catalog.descriptor(for: 1))
        for bytes: [UInt8] in [[], [1], [1, 1, 0], [2, 0, 0], [1, 65, 0], [1, 0, 0, 0]] {
            XCTAssertThrowsError(try SignalCatalog(decoding: Data(bytes), token: 1))
        }
        XCTAssertThrowsError(try SignalCatalog(decoding: Data([1, 0, 0]), token: 0))
        XCTAssertThrowsError(try SignalCatalog(decoding: Data(repeating: 0, count: 16_385), token: 1))
    }
    func testDescriptorsRejectMalformedMetadataAtomically() throws {
        let valid = fields()
        let descriptor = try SignalCatalog(decoding: document([body(valid)]), token: 1).descriptors[0]
        XCTAssertEqual(descriptor.type, .known(.number))
        XCTAssertEqual(descriptor.unit, "future-unit")
        XCTAssertEqual(descriptor.evidence, "future-evidence")
        XCTAssertEqual(try SignalCatalog(decoding: document([body(valid + [(99, Data([4]))])]), token: 1).descriptors[0], descriptor)
        var invalid = [Array(valid.dropFirst()), valid + [(1, Data("other".utf8))],
                       valid + [(99, Data()), (99, Data())]]
        for (tag, bytes) in [(UInt8(1), Data()), (1, Data([0xff])), (1, Data(repeating: 97, count: 64)),
                             (2, Data()), (2, Data([2, 2])), (3, Data(repeating: 97, count: 32)),
                             (4, Data()), (4, Data([0xff]))] {
            invalid.append(valid.map { $0.0 == tag ? (tag, bytes) : $0 })
        }
        invalid.append(valid + [(5, choiceData([(1, "one")]))])
        for fields in invalid {
            XCTAssertThrowsError(try SignalCatalog(decoding: document([body(fields)]), token: 1))
        }
        XCTAssertThrowsError(try SignalCatalog(decoding: document([body(valid, handle: 0)]), token: 1))
        XCTAssertThrowsError(try SignalCatalog(decoding: document([body(valid), body(valid, handle: 2)]), token: 1))
        XCTAssertThrowsError(try SignalCatalog(decoding: document([body(valid), body(fields(key: "different"))]), token: 1))
        let encoded = document([body(valid)])
        for length in 0..<encoded.count {
            XCTAssertThrowsError(try SignalCatalog(decoding: encoded.prefix(length), token: 1))
        }
    }

    func testEnumsOpaqueTypesAndUTF8Bounds() throws {
        let enumFields = fields(type: 3, unit: "none")
        let choices = choiceData([(1, "off"), (2, "reverse")])
        XCTAssertEqual(try SignalCatalog(decoding: document([body(enumFields + [(5, choices)])]), token: 1)
            .descriptors[0].choices.map(\.key), ["off", "reverse"])
        let invalidChoices = [choiceData([]), choiceData([(0, "off")]), choiceData([(1, "")]),
            choiceData([(1, "same"), (2, "same")]), choiceData([(1, "off"), (1, "on")]),
            choiceData([(1, String(repeating: "a", count: 64))]), choices + Data([0]), Data([33, 0]), Data([1, 0, 1, 0, 1, 0xff])]
        for choices in invalidChoices {
            XCTAssertThrowsError(try SignalCatalog(decoding: document([body(enumFields + [(5, choices)])]), token: 1))
        }
        XCTAssertThrowsError(try SignalCatalog(decoding: document([body(enumFields)]), token: 1))
        for type: UInt8 in [1, 3] {
            XCTAssertThrowsError(try SignalCatalog(decoding: document([body(fields(type: type))]), token: 1))
        }
        let opaque = try SignalCatalog(decoding: document([body(fields(type: 127))]), token: 1)
        XCTAssertEqual(opaque.descriptors[0].type, .unknown(127))
        let utf8Key = String(repeating: "é", count: 31) + "x"
        XCTAssertEqual(try SignalCatalog(decoding: document([body(fields(key: utf8Key))]), token: 1).descriptors[0].key, utf8Key)
        XCTAssertThrowsError(try SignalCatalog(decoding: document([body(fields(key: utf8Key + "x"))]), token: 1))
        XCTAssertEqual(try SignalCatalog(decoding: document((1...64).map { body(fields(key: "key\($0)"), handle: UInt16($0)) }), token: 1).descriptors.count, 64)
        let maximumChoices = choiceData((1...32).map { (UInt16($0), "key\($0)") })
        XCTAssertEqual(try SignalCatalog(decoding: document([body(enumFields + [(5, maximumChoices)])]), token: 1).descriptors[0].choices.count, 32)
    }

    func testPageAndSelectorBounds() throws {
        let terminal = Data([1, 1, 0, 0, 0, 3, 0, 3, 0, 0, 0])
        XCTAssertTrue(try SignalCatalogPage(decoding: terminal).data.isEmpty)
        for index in [0, 1, 5, 7, 9] {
            var invalid = terminal
            invalid[index] = index == 0 ? 2 : (index == 1 ? 0 : 255)
            XCTAssertThrowsError(try SignalCatalogPage(decoding: invalid))
        }
        XCTAssertThrowsError(try SignalCatalogPage(decoding: terminal + Data([0])))
        let selector = try SignalCatalogSelector(token: 1, offset: 16_384)
        XCTAssertEqual(try SignalCatalogSelector(decoding: selector.encoded), selector)
        XCTAssertThrowsError(try SignalCatalogSelector(token: 0, offset: 0))
        XCTAssertThrowsError(try SignalCatalogSelector(token: 1, offset: 16_385))
        XCTAssertThrowsError(try SignalCatalogSelector(decoding: selector.encoded + Data([0])))
    }

    func testDeviceInfoExtensionIsAdditiveAndConservative() throws {
        let base = Data([1, 1, 1, 0, 2, 0, 0, 4, 0, 0])
        let legacy = try DeviceInfo(decoding: base)
        XCTAssertFalse(legacy.supportsExtensibleLiveSignals)
        for suffix: [UInt8] in [[1], [1, 0], [2, 1]] {
            let info = try DeviceInfo(decoding: base + Data(suffix))
            XCTAssertFalse(info.supportsExtensibleLiveSignals)
            XCTAssertEqual(info.compatibility(), legacy.compatibility())
        }
        let info = try DeviceInfo(decoding: base + Data([1, 0x81, 99]))
        XCTAssertTrue(info.supportsExtensibleLiveSignals)
        XCTAssertEqual(info.extensionFlags, 0x81)
        XCTAssertEqual(info.liveSignalLayoutVersion, 2)
        XCTAssertEqual(info.compatibility(), legacy.compatibility())
        var unsupported = info
        unsupported.protocolMajor = 2
        XCTAssertFalse(unsupported.supportsExtensibleLiveSignals)
        unsupported = info
        unsupported.protocolMinor = 0
        XCTAssertFalse(unsupported.supportsExtensibleLiveSignals)
    }

    private func fields(key: String = "example.number", type: UInt8 = 2, unit: String = "future-unit") -> [(UInt8, Data)] {
        [(1, Data(key.utf8)), (2, Data([type])), (3, Data(unit.utf8)), (4, Data("future-evidence".utf8))]
    }

    private func body(_ fields: [(UInt8, Data)], handle: UInt16 = 1) -> Data {
        var data = Data()
        data.appendLittleEndian(handle)
        for (tag, value) in fields {
            data.append(tag)
            data.appendLittleEndian(UInt16(value.count))
            data.append(value)
        }
        return data
    }

    private func document(_ bodies: [Data]) -> Data {
        var data = Data([1])
        data.appendLittleEndian(UInt16(bodies.count))
        for body in bodies {
            data.appendLittleEndian(UInt16(body.count))
            data.append(body)
        }
        return data
    }

    private func choiceData(_ choices: [(UInt16, String)]) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt16(choices.count))
        for (handle, key) in choices {
            data.appendLittleEndian(handle)
            data.append(UInt8(key.utf8.count))
            data.append(contentsOf: key.utf8)
        }
        return data
    }
}
