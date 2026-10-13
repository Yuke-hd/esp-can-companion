import XCTest
import BLETransport
import CompanionProtocol
@testable import CompanionLink

@MainActor
final class ExtensibleDemoTests: XCTestCase {
    func testDemoCatalogPagesAndSelectorErrorsKeepConfigIndependent() throws {
        let demo = DemoController()
        let info = try DeviceInfo(decoding: demo.read(CompanionGATT.deviceInfo).get())
        XCTAssertTrue(info.supportsExtensibleLiveSignals)
        var document = Data()
        var page = try SignalCatalogPage(decoding: demo.read(CompanionGATT.signalCatalog).get())
        while true {
            document.append(page.data)
            if document.count == Int(page.totalBytes) { break }
            XCTAssertNil(demo.write(try SignalCatalogSelector(token: page.token, offset: UInt16(document.count)).encoded,
                                    to: CompanionGATT.signalCatalog))
            page = try SignalCatalogPage(decoding: demo.read(CompanionGATT.signalCatalog).get())
        }
        let catalog = try SignalCatalog(decoding: document, token: page.token)
        XCTAssertEqual(catalog, DemoSignalCatalog.vehicle.catalog)
        XCTAssertEqual(catalog.descriptors.count, 21)
        XCTAssertEqual(Set(catalog.descriptors.map(\.unit)), ["none", "rpm", "km/h", "m/s^2"])
        XCTAssertTrue(catalog.descriptors.allSatisfy { $0.evidence == "reference" })
        let selected = try demo.read(CompanionGATT.signalCatalog).get()
        XCTAssertEqual(demo.write(Data([1]), to: CompanionGATT.signalCatalog), .att(0x0D))
        XCTAssertEqual(demo.write(Data([2, 0, 0, 0, 0, 0, 0]), to: CompanionGATT.signalCatalog), .att(0x81))
        XCTAssertEqual(demo.write(try SignalCatalogSelector(token: 1, offset: 0).encoded, to: CompanionGATT.signalCatalog), .att(0x83))
        XCTAssertEqual(try demo.read(CompanionGATT.signalCatalog).get(), selected)
        XCTAssertEqual(demo.activeDocument, DemoController.factoryDocument)
        _ = demo.read(CompanionGATT.deviceInfo)
        XCTAssertEqual(try SignalCatalogPage(decoding: demo.read(CompanionGATT.signalCatalog).get()).offset, 0)
    }

    func testGenericFixtureAddsSignalAndChoiceWithoutFixedLayoutChanges() throws {
        let fixture = try DemoSignalCatalog(token: 17, entries: [
            .init(handle: 92, key: "example.signed", type: .number, unit: "m/s^2"),
            .init(handle: 8, key: "example.mode", type: .enumeration, choices: ["idle", "new_choice"]),
            .init(handle: 40, key: "vehicle.brake_pressed", type: .boolean),
        ])
        let packets = try fixture.packets(sequence: .max, readings: [
            "example.signed": .init(availability: .stale, value: .number(-1.25)),
            "example.mode": .init(availability: .freshnessUnverified, value: .enumeration(choiceKey: "new_choice")),
            "vehicle.brake_pressed": .init(availability: .fresh, value: .boolean(true)),
        ], maximumBytes: 17)
        XCTAssertEqual(packets.count, 3)
        XCTAssertEqual(try packets.map { try ExtensibleLiveSignalPacket(decoding: $0).sequence }, [.max, 0, 1])
        var feed = ExtensibleSignalFeed()
        feed.install(catalog: fixture.catalog)
        for packet in packets { XCTAssertNotNil(feed.receive(packet, at: .now)) }
        let snapshot = feed.snapshot(at: .now)
        XCTAssertEqual(snapshot.reading(for: "example.signed"), .init(availability: .stale, value: .number(-1.25)))
        XCTAssertEqual(snapshot.reading(for: "example.mode")?.value, .enumeration(choiceKey: "new_choice"))
        XCTAssertEqual(snapshot.reading(for: "vehicle.brake_pressed")?.availability, .freshnessUnverified)
        XCTAssertThrowsError(try DemoSignalCatalog(token: 1, entries: [
            .init(handle: 1, key: "duplicate", type: .boolean), .init(handle: 2, key: "duplicate", type: .boolean),
        ]))
        XCTAssertThrowsError(try DemoSignalCatalog(token: 1, entries: [.init(handle: 1, key: "bad", type: .boolean, unit: "rpm")]))
        XCTAssertThrowsError(try DemoSignalCatalog(token: 1, entries: [.init(handle: 1, key: String(repeating: "x", count: 64), type: .number)]))
    }

    func testLegacyDriveAdapterPreservesEngineeringUnitsStatusesAndChoices() throws {
        for seconds in [1.0, 5, 8, 11, 13, 16, 18, 22] {
            let frame = DemoTelemetry.driveLaps(at: seconds, sequence: 0)
            let packets = try DemoSignalCatalog.vehicle.packets(sequence: 0, readings: frame.extensibleReadings)
            XCTAssertEqual(packets.count, 1)
            XCTAssertLessThanOrEqual(packets[0].count, 150)
            XCTAssertEqual(try ExtensibleLiveSignalPacket(decoding: packets[0]).records.count, 21)
            var feed = ExtensibleSignalFeed()
            feed.install(catalog: DemoSignalCatalog.vehicle.catalog)
            XCTAssertNotNil(feed.receive(packets[0], at: .now))
            let snapshot = feed.snapshot(at: .now)
            for (key, reading) in frame.extensibleReadings {
                XCTAssertEqual(snapshot.reading(for: key), reading, "\(key) at \(seconds)")
            }
        }
    }

    func testNonfiniteAndWrongChoiceValuesDoNotBecomeUsable() throws {
        let fixture = try DemoSignalCatalog(token: 1, entries: [
            .init(handle: 1, key: "number", type: .number),
            .init(handle: 2, key: "mode", type: .enumeration, choices: ["idle"]),
        ])
        for value in [Float.nan, .infinity, -.infinity] {
            let packet = try fixture.packets(sequence: 0, readings: [
                "number": .init(availability: .fresh, value: .number(value)),
                "mode": .init(availability: .unavailable, value: .enumeration(choiceKey: "absent")),
            ])[0]
            XCTAssertEqual(try ExtensibleLiveSignalPacket(decoding: packet).records.map(\.status), [1, 4])
        }
    }
}
