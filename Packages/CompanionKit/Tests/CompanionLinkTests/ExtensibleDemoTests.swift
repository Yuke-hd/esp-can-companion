import XCTest
import BLETransport
import CompanionProtocol
@testable import CompanionLink

@MainActor
final class ExtensibleDemoTests: XCTestCase {
    private func connected(_ demo: DemoController, latency: TimeInterval = 0,
                           streamBeforeConnectFor: Duration? = nil) async throws -> (FakeRadio, BLETransport.FakeController, ControllerSession) {
        let scheduler = MainActorScheduler()
        let peripheral = BLETransport.FakeController()
        let radio = FakeRadio(controllers: [peripheral], scheduler: scheduler, latency: latency)
        demo.attach(to: radio)
        let manager = ConnectionManager(radio: radio,
                                        store: InMemoryDeviceStore(rememberedDeviceID: peripheral.id), scheduler: scheduler)
        let session = ControllerSession(connection: manager)
        if let streamBeforeConnectFor {
            demo.streamLiveSignals(on: radio, from: peripheral.id, stopAfter: streamBeforeConnectFor)
        }
        manager.start()
        for _ in 0..<800 where session.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.phase, .ready)
        return (radio, peripheral, session)
    }

    func testNamedUnavailableJourneysNeverSelectLegacyNotifier() async throws {
        for scenario in [DemoScenario.discoveredUnsupported, .discoveredUnusable, .discoveredCatalogFailure] {
            let session = scenario.makeSession(latency: 0)
            defer { session.connection.disconnect() }
            for _ in 0..<800 where session.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertEqual(session.phase, .ready)
            var unavailable: CompanionLiveTelemetryUnavailableReason?
            let states = await session.client.extensibleLiveSignals()
            let consumer = Task { @MainActor in
                for await state in states { if case .unavailable(let reason) = state { unavailable = reason } }
            }
            defer { consumer.cancel() }
            for _ in 0..<200 where unavailable == nil { try await Task.sleep(for: .milliseconds(5)) }
            if scenario == .discoveredCatalogFailure {
                guard case .catalogFailure = unavailable else { return XCTFail("expected catalog failure, got \(String(describing: unavailable))") }
            } else {
                XCTAssertEqual(unavailable, .capabilityUnavailable)
            }
            XCTAssertNil(session.connection.selectedLiveNotifier)
            XCTAssertNotNil(session.activeConfig)
        }
    }

    func testNamedMalformedValidPrefixNeverInstallsChangedBoolean() async throws {
        let session = DemoScenario.discoveredMalformed.makeSession(latency: 0)
        defer { session.connection.disconnect() }
        for _ in 0..<800 where session.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        let telemetry = LiveTelemetry(session: session)
        let consumer = Task { await telemetry.run() }
        defer { consumer.cancel() }
        var rejectedPacketSeen = false
        let observation = session.connection.observeNotifications { characteristic, data in
            if characteristic == CompanionGATT.extensibleLiveSignals,
               (try? ExtensibleLiveSignalPacket(decoding: data)) == nil { rejectedPacketSeen = true }
        }
        defer { observation.cancel() }
        for _ in 0..<400 where telemetry.snapshot?.reading(for: "example.enabled")?.value != .boolean(true) {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(telemetry.snapshot?.reading(for: "example.enabled")?.value, .boolean(true))
        for _ in 0..<12000 where !rejectedPacketSeen { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(rejectedPacketSeen)
        XCTAssertEqual(telemetry.snapshot?.reading(for: "example.enabled")?.value, .boolean(true), "a valid False prefix must not be partially installed")
        for _ in 0..<600 where telemetry.snapshot?.isStalled != true { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(telemetry.snapshot?.isStalled, true)
        XCTAssertNil(telemetry.snapshot?.reading(for: "example.enabled")?.value)
    }

    func testNamedReconnectDiscoversNewHandlesEvenWithSameToken() async throws {
        let session = DemoScenario.discoveredReconnect.makeSession(latency: 0)
        defer { session.connection.disconnect() }
        var readyConnections = 0
        let observation = session.connection.observeState { if $0.isConnected { readyConnections += 1 } }
        defer { observation.cancel() }
        for _ in 0..<800 where session.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        let telemetry = LiveTelemetry(session: session)
        let consumer = Task { await telemetry.run() }
        defer { consumer.cancel() }
        for _ in 0..<400 where telemetry.snapshot?.reading(for: "example.enabled")?.value != .boolean(true) {
            try await Task.sleep(for: .milliseconds(5))
        }
        let initial = try XCTUnwrap(telemetry.snapshot?.catalog)
        for _ in 0..<1600 where session.phase == .ready { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotEqual(session.phase, .ready)
        await consumer.value
        XCTAssertNil(telemetry.snapshot, "disconnect clears the old connection map")
        for _ in 0..<800 where session.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.phase, .ready)
        let reconnectedConsumer = Task { await telemetry.run() }
        defer { reconnectedConsumer.cancel() }
        for _ in 0..<800 where telemetry.snapshot?.reading(for: "example.enabled")?.value != .boolean(false) {
            try await Task.sleep(for: .milliseconds(5))
        }
        let remapped = try XCTUnwrap(telemetry.snapshot?.catalog)
        XCTAssertGreaterThanOrEqual(readyConnections, 2)
        XCTAssertEqual(telemetry.snapshot?.reading(for: "example.enabled")?.value, .boolean(false))
        XCTAssertEqual(initial.token, remapped.token)
        XCTAssertNotEqual(initial.descriptors.map(\.handle), remapped.descriptors.map(\.handle))
        XCTAssertEqual(telemetry.snapshot?.reading(for: "example.mode")?.value, .enumeration(choiceKey: "new_choice"))
        XCTAssertEqual(telemetry.snapshot?.reading(for: "example.signed")?.value, .number(2.5))
        XCTAssertEqual(session.connection.selectedLiveNotifier, CompanionGATT.extensibleLiveSignals)
    }

    func testExplicitSelectionOmitsRecordsAndKeepsOtherSignalClockIndependent() throws {
        let fixture = try DemoSignalCatalog(token: 2, entries: [
            .init(handle: 1, key: "first", type: .number), .init(handle: 2, key: "second", type: .number),
        ])
        let readings: [String: SignalReading<ExtensibleSignalValue>] = [
            "first": .init(availability: .fresh, value: .number(1)),
            "second": .init(availability: .fresh, value: .number(2)),
        ]
        let start = ContinuousClock.now
        var feed = ExtensibleSignalFeed()
        feed.install(catalog: fixture.catalog)
        _ = feed.receive(try fixture.packets(sequence: 0, readings: readings)[0], at: start)
        let partial = try fixture.packets(sequence: 1, readings: readings, selecting: [2])[0]
        XCTAssertEqual(try ExtensibleLiveSignalPacket(decoding: partial).records.map(\.handle), [2])
        _ = feed.receive(try fixture.packets(sequence: 1, readings: [:], selecting: [])[0], at: start + .seconds(1))
        _ = feed.receive(partial, at: start + .seconds(2))
        XCTAssertEqual(feed.snapshot(at: start + .milliseconds(2999)).reading(for: "first")?.value, .number(1))
        let expired = feed.snapshot(at: start + .seconds(3))
        XCTAssertNil(expired.reading(for: "first")?.value)
        XCTAssertEqual(expired.reading(for: "second")?.value, .number(2))
        XCTAssertFalse(expired.isStalled)
        XCTAssertTrue(try ExtensibleLiveSignalPacket(decoding: fixture.packets(sequence: 2, readings: readings, selecting: [])[0]).records.isEmpty)
        XCTAssertThrowsError(try fixture.packets(sequence: 0, readings: readings, selecting: [99]))
        XCTAssertEqual(try ExtensibleLiveSignalPacket(decoding: fixture.packets(sequence: 0, readings: [:])[0]).records.count, 2)
    }

    func testNegotiatedPartialRecordsRetainThenExpireWhilePeerKeepsUpdating() async throws {
        let fixture = try DemoSignalCatalog(token: 3, entries: [
            .init(handle: 1, key: "first", type: .number), .init(handle: 2, key: "second", type: .number),
        ])
        let demo = DemoController(signalCatalog: fixture)
        let (radio, peripheral, session) = try await connected(demo)
        demo.streamLiveSignals(on: radio, from: peripheral.id, extensibleFrames: { seconds, _ in [
            "first": .init(availability: .fresh, value: .number(1)),
            "second": .init(availability: .fresh, value: .number(Float(seconds))),
        ] }, extensibleSelection: { $0 < 0.2 ? nil : [2] })
        defer { demo.liveSignalTask?.cancel(); session.connection.disconnect() }
        let states = await session.client.extensibleLiveSignals()
        var current: ExtensibleSignalSnapshot?
        let consumer = Task { @MainActor in
            for await state in states { if case .active(let value) = state { current = value } }
        }
        defer { consumer.cancel() }
        for _ in 0..<200 where current?.reading(for: "first")?.value == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(current?.reading(for: "first")?.value, .number(1))
        for _ in 0..<200 {
            if case .number(let number) = current?.reading(for: "second")?.value, number >= 0.5 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(current?.reading(for: "first")?.value, .number(1), "omission must retain the reading until its own deadline")
        for _ in 0..<800 where current?.reading(for: "first")?.value != nil { try await Task.sleep(for: .milliseconds(5)) }
        let expired = try XCTUnwrap(current)
        XCTAssertNil(expired.reading(for: "first")?.value)
        XCTAssertEqual(expired.reading(for: "second")?.availability, .fresh)
        XCTAssertNotNil(expired.reading(for: "second")?.value)
        XCTAssertFalse(expired.isStalled)
    }

    func testMalformedAndDroppedPacketTransformsDoNotRefreshNegotiatedStream() async throws {
        for malformed in [true, false] {
            let demo = DemoController()
            let (radio, peripheral, session) = try await connected(demo)
            demo.streamLiveSignals(on: radio, from: peripheral.id, transformExtensiblePackets: { seconds, packets in
                seconds < 0.2 ? packets : (malformed ? packets.map { $0 + Data([1]) } : [])
            })
            defer { demo.liveSignalTask?.cancel(); session.connection.disconnect() }
            let states = await session.client.extensibleLiveSignals()
            var current: ExtensibleSignalSnapshot?
            let consumer = Task { @MainActor in
                for await state in states { if case .active(let value) = state { current = value } }
            }
            defer { consumer.cancel() }
            for _ in 0..<200 where current?.reading(for: "vehicle.engine_rpm")?.value == nil { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertNotNil(current?.reading(for: "vehicle.engine_rpm")?.value)
            for _ in 0..<600 where current?.isStalled != true { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertEqual(current?.isStalled, true)
            XCTAssertNil(current?.reading(for: "vehicle.engine_rpm")?.value)
        }
    }

    func testSlowStartupGetsValidFramesBeforeStopAfterThenStalls() async throws {
        let demo = DemoController()
        let (radio, _, session) = try await connected(demo, latency: 0.08, streamBeforeConnectFor: .milliseconds(250))
        defer { demo.liveSignalTask?.cancel(); session.connection.disconnect() }
        let states = await session.client.extensibleLiveSignals()
        var current: ExtensibleSignalSnapshot?
        let consumer = Task { @MainActor in
            for await state in states { if case .active(let value) = state { current = value } }
        }
        defer { consumer.cancel() }
        for _ in 0..<400 where current?.reading(for: "vehicle.engine_rpm")?.value == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(current?.reading(for: "vehicle.engine_rpm")?.value, "startup exceeds stopAfter but active interval must still run")
        for _ in 0..<600 where current?.isStalled != true { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(current?.isStalled, true)
        XCTAssertNil(current?.reading(for: "vehicle.engine_rpm")?.value)
        XCTAssertEqual(radio.notificationRequests.filter { $0.enabled }.map(\.characteristic), [CompanionGATT.extensibleLiveSignals])
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
        guard case .number(let accelerator)? = active.reading(for: "vehicle.accelerator_pedal_position")?.value else {
            return XCTFail("expected normalized accelerator position")
        }
        XCTAssertEqual(accelerator, 0.2, accuracy: 0.0001)
        XCTAssertEqual(active.reading(for: "vehicle.accelerator_pedal_position")?.availability, .freshnessUnverified)
        XCTAssertEqual(active.reading(for: "vehicle.brake_pressure")?.value, .number(0))
        XCTAssertEqual(active.reading(for: "vehicle.brake_pressure")?.availability, .freshnessUnverified)
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
        XCTAssertEqual(catalog.descriptors.count, 23)
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
            let packets = try DemoSignalCatalog.vehicle.packets(sequence: 0, readings: frame.extensibleReadings,
                                                                maximumBytes: 150)
            XCTAssertEqual(packets.count, 2)
            XCTAssertTrue(packets.allSatisfy { $0.count <= 150 })
            let recordCount = try packets.reduce(0) { count, packet in
                let decoded = try ExtensibleLiveSignalPacket(decoding: packet)
                return count + decoded.records.count
            }
            XCTAssertEqual(recordCount, 23)
            var feed = ExtensibleSignalFeed()
            feed.install(catalog: DemoSignalCatalog.vehicle.catalog)
            for packet in packets { XCTAssertNotNil(feed.receive(packet, at: .now)) }
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
