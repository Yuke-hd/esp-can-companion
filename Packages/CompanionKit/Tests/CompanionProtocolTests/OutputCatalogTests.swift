import XCTest
import CompanionFakes
@testable import CompanionProtocol

final class OutputCatalogTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = Bundle.module.url(forResource: "output-catalog", withExtension: "json", subdirectory: "Fixtures/golden-vectors")!
        return try Data(contentsOf: url)
    }

    func testSyntheticReferenceVectorAndUnknownFields() throws {
        let catalog = try OutputCatalog(decoding: fixture())
        XCTAssertEqual(catalog.outputs.map(\.type), ["led_effect", "led_fill", "led_transient", "led_solid"])
        XCTAssertTrue(catalog.outputs.allSatisfy(\.isEditable))
        XCTAssertEqual(catalog.outputs[1].fields.first(where: { $0.kind == "zone" })?.integer("pixels"), 300)
        XCTAssertEqual(catalog.outputs[1].fields.first(where: { $0.kind == "zone" })?.string("pixels_setting"), "pixel_count")
        XCTAssertEqual(catalog.sinks.first?.settings.first?.integer("min"), 100)
        XCTAssertTrue(try OutputCatalog(decoding: Data(#"{"ignored":true,"outputs":[{"type":"x","sink":"s","fields":[{"name":"value","kind":"future","required":true,"ignored":1}]}]}"#.utf8)).outputs[0].isEditable == false)
    }

    func testIntegerAttributeRejectsRoundedUpperBoundWithoutTrapping() throws {
        for value in ["9223372036854775808", "1.5", "-9223372036854777856"] {
            let json = "{\"name\":\"value\",\"kind\":\"integer\",\"required\":true,\"max\":\(value)}"
            let field = try JSONDecoder().decode(OutputCatalog.Field.self, from: Data(json.utf8))
            XCTAssertNil(field.integer("max"), value)
        }
    }

    func testSharedIntegerConversionHandlesFloatingPointLimits() {
        XCTAssertNil(JSONValue.number(Double(Int.max)).integerValue)
        XCTAssertNil(JSONValue.number(.infinity).integerValue)
        XCTAssertNil(JSONValue.number(.nan).integerValue)
        XCTAssertNil(JSONValue.number(1.5).integerValue)
        XCTAssertEqual(JSONValue.number(Double(Int.min)).integerValue, Int.min)
        XCTAssertEqual(JSONValue.number(Double(Int.max).nextDown).integerValue, Int.max - 1023)
    }

    func testCatalogPreservesExactMaximumInteger() throws {
        let json = "{\"name\":\"value\",\"kind\":\"integer\",\"required\":true,\"max\":\(Int.max)}"
        let field = try JSONDecoder().decode(OutputCatalog.Field.self, from: Data(json.utf8))
        XCTAssertEqual(field.integer("max"), Int.max)
    }

    func testMissingOutputsAndDuplicateTypesAreRejected() {
        for json in [
            #"{"sinks":[]}"#,
            #"{"outputs":[{"type":"same","sink":"a","fields":[]},{"type":"same","sink":"b","fields":[]}]}"#,
        ] {
            XCTAssertThrowsError(try OutputCatalog(decoding: Data(json.utf8)))
        }
    }

    func testCapabilityGateDoesNotDependOnExtensionVersion() {
        for (major, minor, version, flags, expected) in [
            (UInt8(1), UInt8(2), UInt8(9), UInt8(2), true),
            (1, 1, 1, 2, false), (1, 2, 1, 1, false), (2, 2, 1, 2, false),
        ] {
            let info = DeviceInfo(protocolMajor: major, protocolMinor: minor, configSchemaVersion: 1,
                                  liveSignalLayoutVersion: 1, flags: 0, maxConfigBytes: 4096,
                                  firmwareVersion: "test", hardwareID: "test", extensionVersion: version,
                                  extensionFlags: flags)
            XCTAssertEqual(info.supportsOutputCatalog, expected)
        }
    }

    func testPagedDiscoveryCachesAndRedownloadsAfterReconnect() async throws {
        let fake = FakeController()
        fake.deviceInfo.protocolMinor = 2
        fake.deviceInfo.extensionVersion = 1
        fake.deviceInfo.extensionFlags = 0x02
        fake.outputCatalogDocument = try fixture()
        let client = CompanionClient(transport: fake, timeouts: .init(operation: .seconds(1)))
        try await client.readDeviceInfo()
        let first = try await client.discoverOutputCatalog()
        XCTAssertEqual(first.outputs.count, 4)
        XCTAssertEqual(fake.writes.filter { $0.0 == .outputCatalog }.map(\.1),
                       stride(from: 200, to: fake.outputCatalogDocument.count, by: 200).map {
                           (try? SignalCatalogSelector(token: fake.catalogToken, offset: UInt16($0)).encoded) ?? Data()
                       })
        let reads = fake.reads
        let cached = try await client.discoverOutputCatalog()
        XCTAssertEqual(cached, first)
        XCTAssertEqual(fake.reads, reads)
        await client.reset()
        try await client.readDeviceInfo()
        let redownloaded = try await client.discoverOutputCatalog()
        XCTAssertEqual(redownloaded, first)
        XCTAssertGreaterThan(fake.reads, reads)
    }

    func testUnsupportedDeviceDoesNotReadOutputCatalog() async throws {
        let fake = FakeController()
        let client = CompanionClient(transport: fake)
        try await client.readDeviceInfo()
        do {
            _ = try await client.discoverOutputCatalog()
            XCTFail("Expected the capability gate to reject discovery")
        } catch {
            XCTAssertEqual(error as? CompanionClientError, .outputCatalogUnavailable)
        }
        XCTAssertFalse(fake.writes.contains { $0.0 == .outputCatalog })
    }
}
