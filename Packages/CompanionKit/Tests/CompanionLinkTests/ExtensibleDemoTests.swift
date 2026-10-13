import XCTest
import BLETransport
import CompanionProtocol
@testable import CompanionLink

@MainActor
final class ExtensibleDemoTests: XCTestCase {
    private func connected(_ demo: DemoController) async throws -> (FakeRadio, BLETransport.FakeController, ControllerSession) {
        let scheduler = MainActorScheduler()
        let peripheral = BLETransport.FakeController()
        let radio = FakeRadio(controllers: [peripheral], scheduler: scheduler, latency: 0)
        demo.attach(to: radio)
        let manager = ConnectionManager(radio: radio,
                                        store: InMemoryDeviceStore(rememberedDeviceID: peripheral.id), scheduler: scheduler)
        let session = ControllerSession(connection: manager)
        manager.start()
        for _ in 0..<200 where session.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.phase, .ready)
        return (radio, peripheral, session)
    }

    func testNegotiatedDemoUsesCompleteCatalogAndOnlyExtensibleNotifier() async throws {
        let demo = DemoController()
        let (radio, peripheral, session) = try await connected(demo)
        demo.streamLiveSignals(on: radio, from: peripheral.id)
        defer { demo.liveSignalTask?.cancel(); session.connection.disconnect() }
        let states = await session.client.extensibleLiveSignals()
        var snapshot: ExtensibleSignalSnapshot?
        let consumer = Task { @MainActor in
            for await state in states {
                if case .active(let value) = state, value.reading(for: "vehicle.engine_rpm")?.value != nil {
                    snapshot = value
                }
            }
        }
        defer { consumer.cancel() }
        for _ in 0..<200 where snapshot == nil { try await Task.sleep(for: .milliseconds(5)) }
        let active = try XCTUnwrap(snapshot)
        XCTAssertEqual(active.catalog, DemoSignalCatalog.vehicle.catalog)
        XCTAssertEqual(active.reading(for: "vehicle.turn_state")?.value, .enumeration(choiceKey: "left"))
        XCTAssertEqual(active.reading(for: "vehicle.engine_rpm")?.availability, .freshnessUnverified)
        XCTAssertEqual(active.reading(for: "vehicle.brake_pressed")?.availability, .freshnessUnverified)
        XCTAssertTrue(radio.receivedWrites.contains { $0.characteristic == CompanionGATT.signalCatalog })
        XCTAssertEqual(radio.notificationRequests.filter { $0.enabled }.map(\.characteristic), [CompanionGATT.extensibleLiveSignals])
    }

    func testNegotiatedCustomFixturePublishesNewSignalAndChoiceThroughRadio() async throws {
        let fixture = try DemoSignalCatalog(token: 77, entries: [
            .init(handle: 93, key: "example.new_number", type: .number, unit: "m/s^2"),
            .init(handle: 15, key: "example.mode", type: .enumeration, choices: ["idle", "new_choice"]),
        ])
        let demo = DemoController(signalCatalog: fixture)
        let (radio, peripheral, session) = try await connected(demo)
        demo.streamLiveSignals(on: radio, from: peripheral.id, extensibleFrames: { _, _ in [
            "example.new_number": .init(availability: .stale, value: .number(-1.25)),
            "example.mode": .init(availability: .freshnessUnverified, value: .enumeration(choiceKey: "new_choice")),
        ] })
        defer { demo.liveSignalTask?.cancel(); session.connection.disconnect() }
        let states = await session.client.extensibleLiveSignals()
        var snapshot: ExtensibleSignalSnapshot?
        let consumer = Task { @MainActor in
            for await state in states {
                if case .active(let value) = state, value.reading(for: "example.mode")?.value != nil { snapshot = value }
            }
        }
        defer { consumer.cancel() }
        for _ in 0..<200 where snapshot == nil { try await Task.sleep(for: .milliseconds(5)) }
        let active = try XCTUnwrap(snapshot)
        XCTAssertEqual(active.catalog, fixture.catalog)
        XCTAssertEqual(active.reading(for: "example.new_number"), .init(availability: .stale, value: .number(-1.25)))
        XCTAssertEqual(active.reading(for: "example.mode")?.value, .enumeration(choiceKey: "new_choice"))
        XCTAssertEqual(radio.notificationRequests.filter { $0.enabled }.map(\.characteristic), [CompanionGATT.extensibleLiveSignals])
    }

    func testPreExtensionDemoNegotiatesUnavailableWithoutLegacyFallback() async throws {
        var info = DemoController.defaultDeviceInfo
        info.protocolMinor = 0
        info.extensionVersion = nil
        info.extensionFlags = nil
        let demo = DemoController(deviceInfo: info)
        let (radio, _, session) = try await connected(demo)
        defer { session.connection.disconnect() }
        let states = await session.client.extensibleLiveSignals()
        var unavailable: CompanionLiveTelemetryUnavailableReason?
        let consumer = Task { @MainActor in
            for await state in states { if case .unavailable(let reason) = state { unavailable = reason } }
        }
        defer { consumer.cancel() }
        for _ in 0..<200 where unavailable == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(unavailable, .capabilityUnavailable)
        XCTAssertTrue(radio.notificationRequests.isEmpty)
        XCTAssertFalse(radio.receivedWrites.contains { $0.characteristic == CompanionGATT.signalCatalog })
    }

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
