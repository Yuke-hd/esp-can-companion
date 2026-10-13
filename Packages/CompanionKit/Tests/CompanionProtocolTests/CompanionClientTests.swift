import XCTest
@testable import CompanionProtocol
import CompanionFakes

final class CompanionClientTests: XCTestCase {
    private var controller: FakeController!
    private var client: CompanionClient!

    override func setUp() async throws {
        controller = FakeController()
        client = CompanionClient(
            transport: controller,
            timeouts: .init(operation: .milliseconds(200), commit: .milliseconds(400))
        )
    }

    private func connect() async throws {
        try await client.readDeviceInfo()
    }

    private func factoryDocument() throws -> Data {
        try XCTUnwrap(Fixtures.configDocuments()["controller-config-v1.json"])
    }

    private func assertThrows<T>(
        _ expected: CompanionClientError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CompanionClientError, expected, file: file, line: line)
        }
    }

    // MARK: Device info and compatibility

    func testReadsDeviceInfoAndReportsCompatibility() async throws {
        let info = try await client.readDeviceInfo()
        XCTAssertEqual(info, controller.deviceInfo)
        XCTAssertEqual(info.compatibility(), Compatibility(
            isProtocolSupported: true, hasNewerMinor: false, canEditConfig: true, canDecodeLiveSignals: true
        ))
    }

    func testNewerMinorIsCompatible() {
        let info = DeviceInfo(
            protocolMajor: 1, protocolMinor: 4, configSchemaVersion: 1, liveSignalLayoutVersion: 1,
            flags: 0xFE, maxConfigBytes: 4096, firmwareVersion: "", hardwareID: ""
        )
        let compatibility = info.compatibility()
        XCTAssertTrue(compatibility.isProtocolSupported)
        XCTAssertTrue(compatibility.hasNewerMinor)
        XCTAssertFalse(info.isPairingWindowOpen, "Unknown flag bits are ignored")
    }

    func testUnsupportedSchemaAndLayoutAreReported() {
        let info = DeviceInfo(
            protocolMajor: 1, protocolMinor: 0, configSchemaVersion: 2, liveSignalLayoutVersion: 3,
            flags: 0, maxConfigBytes: 4096, firmwareVersion: "", hardwareID: ""
        )
        XCTAssertEqual(info.compatibility(), Compatibility(
            isProtocolSupported: true, hasNewerMinor: false, canEditConfig: false, canDecodeLiveSignals: false
        ))
    }

    func testLiveSignalLayoutsOneAndTwoAreDecodableButNotOthers() {
        func canDecode(layout: UInt8) -> Bool {
            DeviceInfo(
                protocolMajor: 1, protocolMinor: 0, configSchemaVersion: 1, liveSignalLayoutVersion: layout,
                flags: 0, maxConfigBytes: 4096, firmwareVersion: "", hardwareID: ""
            ).compatibility().canDecodeLiveSignals
        }
        XCTAssertTrue(canDecode(layout: 1))
        XCTAssertTrue(canDecode(layout: 2))
        XCTAssertFalse(canDecode(layout: 0))
        XCTAssertFalse(canDecode(layout: 3))
        XCTAssertEqual(CompanionProtocol.supportedLiveSignalLayouts, [1, 2])
    }

    func testEveryOperationNeedsDeviceInfoFirst() async throws {
        await assertThrows(.deviceInfoNotRead) { try await self.client.readConfigStatus() }
        await assertThrows(.deviceInfoNotRead) { try await self.client.readActiveConfig() }
        await assertThrows(.deviceInfoNotRead) { try await self.client.uploadConfig(document: Data("{}".utf8)) }
        await assertThrows(.deviceInfoNotRead) { try await self.client.send(.clearBonds) }
        await assertThrows(.deviceInfoNotRead) { try await self.client.liveSignals() }
        XCTAssertTrue(controller.configWrites.isEmpty)
    }

    func testUnsupportedMajorBlocksEveryOperation() async throws {
        controller.deviceInfo.protocolMajor = 2
        let info = try await client.readDeviceInfo()
        XCTAssertFalse(info.compatibility().isProtocolSupported)
        let expected = CompanionClientError.unsupportedProtocol(major: 2)
        await assertThrows(expected) { try await self.client.readConfigStatus() }
        await assertThrows(expected) { try await self.client.readActiveConfig() }
        await assertThrows(expected) { try await self.client.uploadConfig(document: try self.factoryDocument()) }
        await assertThrows(expected) { try await self.client.send(.revertToFactory) }
        await assertThrows(expected) { try await self.client.liveSignals() }
        XCTAssertTrue(controller.configWrites.isEmpty)
        XCTAssertTrue(controller.commandWrites.isEmpty)
    }

    func testResetForgetsDeviceInfo() async throws {
        try await connect()
        await client.reset()
        await assertThrows(.deviceInfoNotRead) { try await self.client.readConfigStatus() }
    }

    // MARK: Upload

    func testUploadSendsAbortStartChunksAndCommit() async throws {
        try await connect()
        let document = try factoryDocument()
        let progress = LockedValue<[ConfigUploadProgress]>([])
        let receipt = try await client.uploadConfig(document: document) { update in
            progress.withValue { $0.append(update) }
        }

        let writes = controller.configWrites
        XCTAssertEqual(writes.first, ConfigWritePDU.abort.encoded)
        XCTAssertEqual(writes[1], ConfigWritePDU.start(totalLength: UInt16(document.count), crc32: CRC32.checksum(document)).encoded)
        XCTAssertEqual(writes.last, ConfigWritePDU.commit.encoded)
        let chunks = writes.dropFirst(2).dropLast()
        XCTAssertEqual(chunks.count, Int((Double(document.count) / 241).rounded(.up)))
        XCTAssertTrue(chunks.allSatisfy { $0.count <= controller.maximumWrite })
        XCTAssertEqual(Data(chunks.flatMap { $0.dropFirst(3) }), document)

        XCTAssertEqual(receipt, ConfigUploadReceipt(savedLength: UInt16(document.count), savedCRC32: CRC32.checksum(document)))
        XCTAssertEqual(progress.get().first, ConfigUploadProgress(sentBytes: 0, totalBytes: document.count))
        XCTAssertEqual(progress.get().last?.fraction, 1)
        XCTAssertEqual(controller.subscriberCount, 0, "The status subscription ends with the upload")
    }

    func testUploadAtMinimumMTUUses58ByteChunks() async throws {
        controller.maximumWrite = 61
        try await connect()
        _ = try await client.uploadConfig(document: try factoryDocument())
        let chunks = controller.configWrites.filter { $0.first == 0x02 }
        XCTAssertEqual(chunks.map { $0.count - 3 }.max(), 58)
    }

    func testUploadOfModelEncodesCanonicalJSON() async throws {
        try await connect()
        let document = try factoryDocument()
        let config = try ControllerConfig(canonicalJSON: document)
        let receipt = try await client.uploadConfig(config)
        XCTAssertEqual(receipt.savedCRC32, CRC32.checksum(document))
    }

    func testUploadIsActiveAfterRestart() async throws {
        try await connect()
        let document = try factoryDocument()
        let receipt = try await client.uploadConfig(document: document)
        // The controller restarts into the saved override.
        controller.withLock {
            controller.state = 0
            controller.result = 0
            controller.activeSource = 1
            controller.activeDocument = document
        }
        let isActive = try await client.isUploadActive(receipt)
        XCTAssertTrue(isActive)

        controller.withLock { controller.activeSource = 0 }
        let isActiveAfterFallback = try await client.isUploadActive(receipt)
        XCTAssertFalse(isActiveAfterFallback)
    }

    func testRejectsDocumentsTheControllerCannotTake() async throws {
        try await connect()
        await assertThrows(.emptyDocument) { try await self.client.uploadConfig(document: Data()) }
        await assertThrows(.documentTooLarge(size: 4097, maximum: 4096)) {
            try await self.client.uploadConfig(document: Data(repeating: 0x20, count: 4097))
        }
        await assertThrows(.configSchemaMismatch(document: 2, controller: 1)) {
            try await self.client.uploadConfig(document: Data(#"{"version":2}"#.utf8))
        }
        XCTAssertTrue(controller.configWrites.isEmpty)
    }

    func testRefusesDocumentsWithoutAReadableVersion() async throws {
        try await connect()
        for document in [#"{"actions":[]}"#, #"{"version":1.5}"#, #"{"version":"1"}"#, "not json"] {
            await assertThrows(.unreadableDocumentVersion) {
                try await self.client.uploadConfig(document: Data(document.utf8))
            }
        }
        XCTAssertTrue(controller.configWrites.isEmpty)
    }

    func testSchemaMismatchWithNewerController() async throws {
        controller.deviceInfo.configSchemaVersion = 2
        try await connect()
        await assertThrows(.configSchemaMismatch(document: 1, controller: 2)) {
            try await self.client.uploadConfig(ControllerConfig())
        }
        XCTAssertTrue(controller.configWrites.isEmpty)
    }

    func testMTUBelow64IsRefused() async throws {
        controller.maximumWrite = 60
        try await connect()
        await assertThrows(.mtuTooSmall(maximumWriteLength: 60)) {
            try await self.client.uploadConfig(document: try self.factoryDocument())
        }
        XCTAssertTrue(controller.configWrites.isEmpty)
    }

    func testResumesAfterOffsetMismatch() async throws {
        try await connect()
        let document = try factoryDocument()
        let chunksSeen = LockedValue(0)
        controller.beforeWrite = { fake, _, value in
            guard value.first == 0x02 else { return }
            // Before the third chunk, the controller holds fewer bytes than the
            // client thinks, so the client must resync from Config status.
            if chunksSeen.withValue({ $0 += 1; return $0 }) == 3 {
                fake.buffer.removeLast(10)
            }
        }
        let receipt = try await client.uploadConfig(document: document)
        XCTAssertEqual(receipt.savedCRC32, CRC32.checksum(document))
    }

    func testOffsetMismatchOnAnotherTransferFails() async throws {
        try await connect()
        controller.beforeWrite = { fake, _, value in
            // The controller now holds a different transfer, so resuming is unsafe.
            if value.first == 0x02, fake.buffer.count > 0 {
                fake.buffer.removeLast()
                fake.transferLength = 4000
            }
        }
        await assertThrows(.controllerError(.known(.offsetMismatch), step: .chunk)) {
            try await self.client.uploadConfig(document: try self.factoryDocument())
        }
    }

    func testConfigRejectionCarriesCodeAndPath() async throws {
        controller.commitOutcome = .reject(category: 3, code: 10, validation: 18, index: 3, path: "outputs[3].zone.length")
        try await connect()
        await assertThrows(.configRejected(ConfigRejection(
            category: .known(.semantic), code: .known(.schemaValidation), validation: .known(.zoneOutOfRange),
            index: 3, path: "outputs[3].zone.length", isPathTruncated: false
        ))) {
            try await self.client.uploadConfig(document: try self.factoryDocument())
        }
    }

    func testApplyRejectionCarriesStage() async throws {
        controller.commitOutcome = .applyReject(stage: 5, section: 2, index: 1, engine: 6)
        try await connect()
        await assertThrows(.applyRejected(ApplyRejection(
            stage: .known(.rule), validation: .known(.none), section: .known(.rules), index: 1,
            binding: .known(.ok), engine: .known(.unknownSignal)
        ))) {
            try await self.client.uploadConfig(document: try self.factoryDocument())
        }
    }

    func testStorageFailureIsReported() async throws {
        controller.commitOutcome = .storageFailure
        try await connect()
        await assertThrows(.storageFailed) { try await self.client.uploadConfig(document: try self.factoryDocument()) }
    }

    func testChecksumMismatchIsReported() async throws {
        try await connect()
        controller.beforeWrite = { fake, _, value in
            if value.first == 0x03 { fake.buffer[0] ^= 0xFF }
        }
        await assertThrows(.checksumMismatch) { try await self.client.uploadConfig(document: try self.factoryDocument()) }
        XCTAssertEqual(controller.result, 7)
    }

    func testDisconnectDuringCommitIsUnknownOutcome() async throws {
        controller.commitOutcome = .dropLink
        try await connect()
        await assertThrows(.commitOutcomeUnknown) { try await self.client.uploadConfig(document: try self.factoryDocument()) }
    }

    func testOtherLinkFailureDuringCommitIsUnknownOutcome() async throws {
        try await connect()
        controller.beforeWrite = { _, _, value in
            if value == ConfigWritePDU.commit.encoded { throw CompanionTransportError.other("link failed") }
        }
        await assertThrows(.commitOutcomeUnknown) { try await self.client.uploadConfig(document: try self.factoryDocument()) }
    }

    func testNotConnectedDuringCommitIsAPlainFailure() async throws {
        try await connect()
        controller.beforeWrite = { _, _, value in
            if value == ConfigWritePDU.commit.encoded { throw CompanionTransportError.notConnected }
        }
        await assertThrows(.transport(.notConnected)) { try await self.client.uploadConfig(document: try self.factoryDocument()) }
    }

    func testCommitTimeoutIsUnknownOutcome() async throws {
        try await connect()
        controller.beforeWrite = { fake, _, value in
            if value.first == 0x02, fake.buffer.count + value.count - 3 == fake.transferLength {
                fake.hangingWrites = [.config]
            }
        }
        await assertThrows(.commitOutcomeUnknown) { try await self.client.uploadConfig(document: try self.factoryDocument()) }
    }

    func testChunkTimeoutAbortsTheTransfer() async throws {
        try await connect()
        controller.beforeWrite = { fake, _, value in
            if value.first == 0x01 { fake.hangingWrites = [.config] }
        }
        await assertThrows(.timedOut(.chunk)) { try await self.client.uploadConfig(document: try self.factoryDocument()) }
        // The abort also hung, so the controller's idle timeout is the backstop;
        // the client still tried.
        XCTAssertEqual(controller.configWrites.last, ConfigWritePDU.abort.encoded)
    }

    func testControllerErrorDuringStartIsReported() async throws {
        controller.deviceInfo.maxConfigBytes = 8192
        try await connect()
        controller.deviceInfo.maxConfigBytes = 100
        await assertThrows(.controllerError(.known(.tooLarge), step: .start)) {
            try await self.client.uploadConfig(document: try self.factoryDocument())
        }
    }

    func testCancellingAnUploadAbortsIt() async throws {
        try await connect()
        controller.writeDelay = .milliseconds(20)
        let document = try factoryDocument()
        let upload = Task { try await self.client.uploadConfig(document: document) }
        try await Task.sleep(for: .milliseconds(90))
        upload.cancel()
        do {
            _ = try await upload.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(controller.configWrites.last, ConfigWritePDU.abort.encoded)
        XCTAssertEqual(controller.state, 0)
        XCTAssertEqual(controller.result, 5)
        XCTAssertFalse(controller.configWrites.contains(ConfigWritePDU.commit.encoded))
    }

    func testOneUploadAtATime() async throws {
        try await connect()
        controller.writeDelay = .milliseconds(20)
        let document = try factoryDocument()
        let first = Task { try await self.client.uploadConfig(document: document) }
        try await Task.sleep(for: .milliseconds(30))
        await assertThrows(.uploadInProgress) { try await self.client.uploadConfig(document: document) }
        _ = try await first.value
    }

    // MARK: Read-back

    func testReadsActiveConfigAcrossPages() async throws {
        let document = try factoryDocument()
        controller.activeSource = 0
        controller.activeDocument = document
        controller.readPageOffset = 400
        try await connect()

        let readBack = try await client.readActiveConfig()
        XCTAssertEqual(readBack, ConfigReadBack(source: .known(.factory), document: document, crc32: CRC32.checksum(document)))
        XCTAssertEqual(try readBack.decodeConfig().actions.count, 6)
        let selects = controller.configWrites.filter { $0.first == 0x05 }
        XCTAssertEqual(selects.first, ConfigWritePDU.selectReadPage(offset: 0).encoded, "Read-back always starts at 0")
        XCTAssertEqual(selects.count, Int((Double(document.count) / 200).rounded(.up)))
    }

    func testReadsEmptyConfigWhenNoneSelected() async throws {
        controller.activeSource = 0xFF
        controller.activeDocument = Data()
        try await connect()
        let readBack = try await client.readActiveConfig()
        XCTAssertEqual(readBack, ConfigReadBack(source: .known(.none), document: Data(), crc32: 0))
    }

    func testReadBackRetriesWhenPagesDisagree() async throws {
        let document = try factoryDocument()
        controller.activeDocument = document
        let reads = LockedValue(0)
        controller.beforeRead = { fake, characteristic in
            guard characteristic == .config else { return }
            // The second page of the first attempt comes from a different document.
            if reads.withValue({ $0 += 1; return $0 }) == 2 {
                fake.activeDocument = document + Data(" ".utf8)
            } else {
                fake.activeDocument = document
            }
        }
        try await connect()
        let readBack = try await client.readActiveConfig()
        XCTAssertEqual(readBack.document, document)
    }

    func testReadBackGivesUpWhenItNeverSettles() async throws {
        let document = try factoryDocument()
        let reads = LockedValue(0)
        controller.beforeRead = { fake, characteristic in
            guard characteristic == .config else { return }
            let count = reads.withValue { $0 += 1; return $0 }
            fake.activeDocument = document + Data(repeating: 0x20, count: count % 2)
        }
        try await connect()
        await assertThrows(.readBackInconsistent) { try await self.client.readActiveConfig() }
    }

    // MARK: Commands

    func testSendsCommands() async throws {
        try await connect()
        try await client.send(.revertToFactory)
        try await client.send(.clearBonds)
        XCTAssertEqual(controller.commandWrites, [Data([0x01, 0xFE]), Data([0x02, 0xFD])])
    }

    func testCommandDroppedLinkIsUnknownOutcome() async throws {
        try await connect()
        controller.beforeWrite = { _, characteristic, _ in
            if characteristic == .command { throw CompanionTransportError.disconnected }
        }
        await assertThrows(.commandOutcomeUnknown(.clearBonds)) { try await self.client.send(.clearBonds) }
    }

    func testCommandOtherLinkFailureIsUnknownOutcome() async throws {
        try await connect()
        controller.beforeWrite = { _, characteristic, _ in
            if characteristic == .command { throw CompanionTransportError.other(nil) }
        }
        await assertThrows(.commandOutcomeUnknown(.revertToFactory)) { try await self.client.send(.revertToFactory) }
    }

    func testCommandBusyDuringTransfer() async throws {
        try await connect()
        controller.state = 1
        await assertThrows(.controllerError(.known(.busy), step: .command)) { try await self.client.send(.revertToFactory) }
    }

    // MARK: Live signals

    func testLiveSignalsStartUnknownThenStreamFrames() async throws {
        try await connect()
        let stream = try await client.liveSignals(stallTimeout: .seconds(5))
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .unknown)

        var frame = Data([1, 9, 1]) + Data(count: 20)
        frame[13] = 0x09 // engine_rpm: fresh with a value.
        controller.notify(.liveSignals, frame)
        let second = await iterator.next()
        XCTAssertEqual(second?.sequence, 9)
        XCTAssertEqual(second?.engineRPM, SignalReading(availability: .fresh, value: 0))
    }

    func testLiveSignalsGoUnknownWhenStalled() async throws {
        try await connect()
        let stream = try await client.liveSignals(stallTimeout: .milliseconds(80))
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        var frame = Data([1, 1, 1]) + Data(count: 20)
        frame[13] = 0x0B // engine_rpm: unverified with a value.
        controller.notify(.liveSignals, frame)
        let live = await iterator.next()
        XCTAssertEqual(live?.engineRPM.availability, .freshnessUnverified)
        let stalled = await iterator.next()
        XCTAssertEqual(stalled, .unknown)
    }

    func testStallIsReportedAtTheDeadline() async throws {
        try await connect()
        let timeout = Duration.seconds(1)
        let stream = try await client.liveSignals(stallTimeout: timeout)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        let clock = ContinuousClock()
        let sentAt = clock.now
        controller.notify(.liveSignals, Data([1, 1, 1]) + Data(count: 20))
        _ = await iterator.next()
        let stalled = await iterator.next()
        let elapsed = clock.now - sentAt
        XCTAssertEqual(stalled, .unknown)
        XCTAssertGreaterThanOrEqual(elapsed, timeout)
        // Polling at a quarter of the timeout could lag by up to 25%.
        XCTAssertLessThan(elapsed, timeout * 1.2)
    }

    func testSlowConsumerGetsTheNewestFrame() async throws {
        try await connect()
        let stream = try await client.liveSignals(stallTimeout: .seconds(5))
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        for sequence: UInt8 in 1...5 {
            controller.notify(.liveSignals, Data([1, sequence, 1]) + Data(count: 20))
        }
        let next = await iterator.next()
        XCTAssertEqual(next?.sequence, 5)
    }

    func testLiveSignalsDropMalformedFrames() async throws {
        try await connect()
        let stream = try await client.liveSignals(stallTimeout: .seconds(5))
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        controller.notify(.liveSignals, Data([2]) + Data(count: 22))
        controller.notify(.liveSignals, Data([1, 4, 1]) + Data(count: 20))
        let next = await iterator.next()
        XCTAssertEqual(next?.sequence, 4)
    }

    func testLiveSignalsRefuseUnsupportedLayout() async throws {
        controller.deviceInfo.liveSignalLayoutVersion = 3
        try await connect()
        await assertThrows(.unsupportedLiveSignalLayout(3)) { try await self.client.liveSignals() }
        XCTAssertEqual(controller.subscriberCount, 0)
    }

    /// A 28-byte layout 2 frame with longitudinal +1.00 m/s² and lateral -0.500 m/s², both fresh.
    private func layout2Frame(sequence: UInt8) -> Data {
        var frame = Data([2, sequence, 1]) + Data(count: 25)
        frame[22] = 0x91 // Status nibble 19 (longitudinal) fresh with value; nibble 18 (brake) fresh.
        frame[23] = 0x09 // Status nibble 20 (lateral) fresh with value.
        frame[24] = 100
        frame[26] = 0x0C
        frame[27] = 0xFE // -500 = 0xFE0C
        return frame
    }

    func testLayout2ControllerStreamsAcceleration() async throws {
        controller.deviceInfo.liveSignalLayoutVersion = 2
        try await connect()
        let stream = try await client.liveSignals(stallTimeout: .seconds(5))
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        controller.notify(.liveSignals, layout2Frame(sequence: 3))
        let frame = await iterator.next()
        XCTAssertEqual(frame?.longitudinalAcceleration, SignalReading(availability: .fresh, value: 1.0))
        XCTAssertEqual(frame?.lateralAcceleration, SignalReading(availability: .fresh, value: -0.5))
    }

    func testLayout2ControllerDropsLayout1Frames() async throws {
        controller.deviceInfo.liveSignalLayoutVersion = 2
        try await connect()
        let stream = try await client.liveSignals(stallTimeout: .seconds(5))
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        controller.notify(.liveSignals, Data([1, 2, 1]) + Data(count: 20))
        controller.notify(.liveSignals, layout2Frame(sequence: 4))
        let next = await iterator.next()
        XCTAssertEqual(next?.sequence, 4)
    }

    func testLayout1ControllerDropsLayout2Frames() async throws {
        try await connect()
        let stream = try await client.liveSignals(stallTimeout: .seconds(5))
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        controller.notify(.liveSignals, layout2Frame(sequence: 2))
        controller.notify(.liveSignals, Data([1, 5, 1]) + Data(count: 20))
        let next = await iterator.next()
        XCTAssertEqual(next?.sequence, 5)
        XCTAssertEqual(next?.longitudinalAcceleration, .unknown)
    }
}

final class ExtensibleTelemetryNegotiationTests: XCTestCase {
    func testProtocol10KeepsConfigButHasExplicitUnavailableTelemetryWithoutFallback() async throws {
        let fake = FakeController()
        let transport = NegotiationTransport(fake)
        let client = CompanionClient(transport: transport)
        try await client.readDeviceInfo()
        let stream = await client.extensibleLiveSignals()
        var iterator = stream.makeAsyncIterator()
        var state = await iterator.next()
        if state == .discovering { state = await iterator.next() }
        XCTAssertEqual(state, .unavailable(.capabilityUnavailable))
        XCTAssertTrue(transport.activations.get().isEmpty)
        XCTAssertTrue(transport.subscriptions.get().isEmpty)
        _ = try await client.readConfigStatus()
        XCTAssertEqual(fake.subscriberCount, 0)
    }
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "extensible-live-v1", withExtension: "json", subdirectory: "Fixtures/golden-vectors"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func bytes(_ hex: String) -> Data {
        let pairs = stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        return Data(pairs)
    }

    private func connected(timeout: Duration = .seconds(1)) async throws -> (FakeController, NegotiationTransport, CompanionClient) {
        let fake = FakeController()
        fake.deviceInfo.protocolMinor = 1
        fake.deviceInfo.extensionVersion = 1
        fake.deviceInfo.extensionFlags = 1
        fake.catalogToken = 0x12345678
        fake.catalogDocument = bytes((try fixture()["catalog"] as! [String: Any])["document_hex"] as! String)
        let transport = NegotiationTransport(fake)
        let client = CompanionClient(transport: transport, timeouts: .init(operation: timeout))
        try await client.readDeviceInfo()
        return (fake, transport, client)
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate() {
            if ContinuousClock.now >= deadline { XCTFail("Timed out waiting for telemetry state", file: file, line: line); throw TestTimeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func active(_ recorder: TelemetryRecorder) async throws -> ExtensibleSignalSnapshot {
        try await waitUntil { if case .active = recorder.latest { return true }; return false }
        guard case .active(let snapshot) = recorder.latest else { throw TestTimeout() }
        return snapshot
    }

    private func unavailable(_ recorder: TelemetryRecorder) async throws -> CompanionLiveTelemetryUnavailableReason {
        try await waitUntil { if case .unavailable = recorder.latest { return true }; return false }
        guard case .unavailable(let reason) = recorder.latest else { throw TestTimeout() }
        return reason
    }

    func testKnownMinorAndUsableExtensionSubscribeOnlyAfterCompleteDiscoveryAndNeverRenegotiateNormalPackets() async throws {
        let (fake, transport, client) = try await connected()
        XCTAssertFalse(fake.deviceInfo.compatibility().hasNewerMinor)
        fake.catalogPageLength = 11
        let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
        defer { recorder.cancel() }
        let initial = try await active(recorder)
        XCTAssertEqual(initial.catalog?.descriptors.count, 7)
        XCTAssertTrue(initial.signals.allSatisfy { $0.reading == .unknown })
        XCTAssertEqual(transport.activations.get(), [.extensibleLiveSignals])
        XCTAssertEqual(transport.subscriptions.get(), [.extensibleLiveSignals])
        let reads = transport.catalogReads.get()
        for sequence: UInt8 in 1...5 {
            fake.notify(.extensibleLiveSignals, Data([1, sequence, 0, 1, 0x78, 0x56, 0x34, 0x12, 5, 1, 0, 1, 9, 1]))
        }
        try await waitUntil { if case .active(let snapshot) = recorder.latest { return snapshot.sequence == 5 }; return false }
        let snapshot = try await active(recorder)
        XCTAssertEqual(snapshot.reading(for: "example.enabled"), SignalReading(availability: .fresh, value: .boolean(true)))
        XCTAssertEqual(transport.catalogReads.get(), reads)
        XCTAssertEqual(transport.activations.get().count, 1)
        _ = try await client.readConfigStatus()
    }

    func testAbsentUnknownAndUnusableCapabilitiesNeverReadCatalogOrSubscribe() async throws {
        for capability in [(UInt8?.none, UInt8?.none), (2, 1), (1, 0), (1, nil)] {
            let (fake, transport, client) = try await connected()
            fake.deviceInfo.extensionVersion = capability.0
            fake.deviceInfo.extensionFlags = capability.1
            try await client.readDeviceInfo()
            let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
            let reason = try await unavailable(recorder)
            XCTAssertEqual(reason, .capabilityUnavailable)
            XCTAssertEqual(transport.catalogReads.get(), 0)
            XCTAssertTrue(transport.activations.get().isEmpty)
            XCTAssertTrue(transport.subscriptions.get().isEmpty)
            recorder.cancel()
        }
    }

    func testMissingEitherEndpointPublishesUnavailableWithoutFallback() async throws {
        for endpoint in [CompanionCharacteristic.signalCatalog, .extensibleLiveSignals] {
            let (_, transport, client) = try await connected()
            _ = transport.endpoints.withValue { $0.remove(endpoint) }
            let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
            let reason = try await unavailable(recorder)
            XCTAssertEqual(reason, .missingEndpoints)
            XCTAssertEqual(transport.catalogReads.get(), 0)
            XCTAssertTrue(transport.activations.get().isEmpty)
            XCTAssertTrue(transport.subscriptions.get().isEmpty)
            recorder.cancel()
        }
    }

    func testFailedIncompleteAndMalformedCatalogSelectNoNotifierAndLeaveConfigUsable() async throws {
        for failure in 0..<3 {
            let (fake, transport, client) = try await connected(timeout: .milliseconds(40))
            if failure == 0 { fake.hangingReads = [.signalCatalog] }
            if failure == 1 { fake.catalogReadOverride = Data([1, 0x78, 0x56, 0x34, 0x12, 10, 0, 0, 0, 1, 0]) }
            if failure == 2 { fake.catalogDocument = Data([1, 1, 0]) }
            let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
            guard case .catalogFailure = try await unavailable(recorder) else { XCTFail("Expected catalog failure"); continue }
            XCTAssertTrue(transport.activations.get().isEmpty)
            XCTAssertTrue(transport.subscriptions.get().isEmpty)
            let catalog = await client.signalCatalog
            XCTAssertNil(catalog)
            _ = try await client.readConfigStatus()
            recorder.cancel()
        }
    }

    func testNotifierFailureIsExplicitAndDisposesByteSubscription() async throws {
        let (fake, transport, client) = try await connected()
        transport.activationError = .att(.known(.invalidState))
        let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
        guard case .notifierFailure(.controllerError(.known(.invalidState), _)) = try await unavailable(recorder) else { return XCTFail("Expected notifier ATT failure") }
        try await waitUntil { fake.subscriberCount == 0 }
        XCTAssertEqual(transport.activations.get(), [.extensibleLiveSignals])
        recorder.cancel()
    }

    func testSubscribersShareLeaseAndFinalCancellationRestartsUnknownWithCachedImmutableCatalog() async throws {
        let (fake, transport, client) = try await connected()
        let first = TelemetryRecorder(await client.extensibleLiveSignals())
        let initial = try await active(first)
        let second = TelemetryRecorder(await client.extensibleLiveSignals())
        _ = try await active(second)
        let reads = transport.catalogReads.get()
        fake.notify(.extensibleLiveSignals, bytes("0100000178563412050100010901"))
        try await waitUntil { if case .active(let s) = second.latest { return s.sequence == 0 }; return false }
        first.cancel()
        await first.task.value
        XCTAssertEqual(fake.subscriberCount, 1)
        XCTAssertFalse(transport.leases.get()[0].state.get().ended)
        second.cancel()
        await second.task.value
        try await waitUntil { fake.subscriberCount == 0 && transport.leases.get()[0].state.get().ended }
        fake.catalogDocument = Data([1, 0, 0])
        let third = TelemetryRecorder(await client.extensibleLiveSignals())
        defer { third.cancel() }
        let restarted = try await active(third)
        XCTAssertEqual(restarted.catalog, initial.catalog)
        XCTAssertNil(restarted.sequence)
        XCTAssertTrue(restarted.signals.allSatisfy { $0.reading == .unknown })
        XCTAssertEqual(transport.catalogReads.get(), reads)
        XCTAssertEqual(transport.activations.get(), [.extensibleLiveSignals, .extensibleLiveSignals])
    }

    func testTokenMismatchImmediatelyClearsAndSuspendsUntilCompleteRediscovery() async throws {
        let (fake, transport, client) = try await connected()
        let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
        defer { recorder.cancel() }
        _ = try await active(recorder)
        fake.notify(.extensibleLiveSignals, bytes("0100000178563412050100010901"))
        try await waitUntil { if case .active(let s) = recorder.latest { return s.sequence == 0 }; return false }
        fake.withLock { fake.catalogToken = 0x87654321; fake.catalogPageOffset = 0; fake.readDelay = .milliseconds(60) }
        // A mismatched recognizable header invalidates even with malformed records.
        fake.notify(.extensibleLiveSignals, bytes("01010001214365870801000109"))
        try await waitUntil { recorder.latest == .discovering }
        fake.notify(.extensibleLiveSignals, bytes("0102000178563412050100010901"))
        XCTAssertEqual(recorder.latest, .discovering)
        let replacement = try await active(recorder)
        XCTAssertEqual(replacement.catalog?.token, 0x87654321)
        XCTAssertTrue(replacement.signals.allSatisfy { $0.reading == .unknown })
        XCTAssertEqual(transport.activations.get().count, 1)
        XCTAssertEqual(transport.catalogReads.get(), 4)
        fake.notify(.extensibleLiveSignals, bytes("0103000121436587050100010900"))
        try await waitUntil { if case .active(let s) = recorder.latest { return s.sequence == 3 }; return false }
    }

    func testResetReconnectSameTokenRediscoversRemappedHandlesAndRejectsOldCallbacks() async throws {
        let (fake, transport, client) = try await connected()
        let old = TelemetryRecorder(await client.extensibleLiveSignals())
        _ = try await active(old)
        fake.notify(.extensibleLiveSignals, bytes("0100000178563412050100010901"))
        await client.reset()
        let oldReason = try await unavailable(old)
        XCTAssertEqual(oldReason, .connectionEnded)
        var document = fake.catalogDocument
        document[5] = 9
        fake.withLock { fake.catalogDocument = document; fake.catalogPageOffset = 0 }
        try await client.readDeviceInfo()
        let fresh = TelemetryRecorder(await client.extensibleLiveSignals())
        defer { old.cancel(); fresh.cancel() }
        let snapshot = try await active(fresh)
        XCTAssertEqual(snapshot.catalog?.descriptor(for: 9)?.key, "example.enabled")
        XCTAssertNil(snapshot.catalog?.descriptor(for: 1))
        XCTAssertEqual(transport.catalogReads.get(), 4)
        transport.oldHandlers.get()[0](bytes("0109000178563412050100010901"))
        let afterOldCallback = try await active(fresh)
        XCTAssertEqual(afterOldCallback, snapshot)
        fake.notify(.extensibleLiveSignals, bytes("0101000178563412050900010900"))
        try await waitUntil { if case .active(let s) = fresh.latest { return s.sequence == 1 }; return false }
        let received = try await active(fresh)
        XCTAssertEqual(received.reading(for: "example.enabled")?.value, .boolean(false))
    }

    func testRemoteLeaseLossClearsReadingsAndEndsSubscribersWithoutBreakingConfig() async throws {
        let (fake, transport, client) = try await connected()
        let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
        _ = try await active(recorder)
        fake.notify(.extensibleLiveSignals, bytes("0100000178563412050100010901"))
        transport.leases.get()[0].cancel()
        let reason = try await unavailable(recorder)
        XCTAssertEqual(reason, .notifierEnded)
        try await waitUntil { fake.subscriberCount == 0 }
        let catalog = await client.signalCatalog
        XCTAssertNotNil(catalog)
        _ = try await client.readConfigStatus()
        await recorder.task.value
    }

    func testAlreadyEndedLeaseNeverPublishesActiveSnapshot() async throws {
        let (_, transport, client) = try await connected()
        transport.endBeforeReturningLease = true
        let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
        let reason = try await unavailable(recorder)
        XCTAssertEqual(reason, .notifierEnded)
        XCTAssertFalse(recorder.values.get().contains { if case .active = $0 { return true }; return false })
    }

    func testCancelledUncancellableActivationDisposesLateLeaseAndCannotAffectRestart() async throws {
        let (fake, transport, client) = try await connected()
        transport.activationDelay = .milliseconds(80)
        let old = TelemetryRecorder(await client.extensibleLiveSignals())
        try await waitUntil { transport.activations.get().count == 1 }
        old.cancel()
        await old.task.value
        let fresh = TelemetryRecorder(await client.extensibleLiveSignals())
        defer { fresh.cancel() }
        _ = try await active(fresh)
        try await waitUntil { transport.leases.get().count == 2 }
        XCTAssertTrue(transport.leases.get()[0].state.get().ended)
        XCTAssertFalse(transport.leases.get()[1].state.get().ended)
        XCTAssertEqual(fake.subscriberCount, 1)
    }


    func testResetDuringDiscoveryRejectsLateMapAndCannotSelectForOldGeneration() async throws {
        let (fake, transport, client) = try await connected()
        fake.readDelay = .milliseconds(80)
        let old = TelemetryRecorder(await client.extensibleLiveSignals())
        try await waitUntil { transport.catalogReads.get() == 1 }
        await client.reset()
        let reason = try await unavailable(old)
        XCTAssertEqual(reason, .connectionEnded)
        fake.withLock { fake.readDelay = nil; fake.catalogDocument = Data([1, 0, 0]); fake.catalogPageOffset = 0 }
        try await client.readDeviceInfo()
        let fresh = TelemetryRecorder(await client.extensibleLiveSignals())
        defer { old.cancel(); fresh.cancel() }
        let snapshot = try await active(fresh)
        XCTAssertTrue(snapshot.signals.isEmpty)
        XCTAssertEqual(transport.activations.get(), [.extensibleLiveSignals])
    }

    func testActivationTimeoutIsBoundedAndLateLeaseIsDisposed() async throws {
        let (fake, transport, client) = try await connected(timeout: .milliseconds(30))
        transport.activationDelay = .milliseconds(80)
        let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
        let reason = try await unavailable(recorder)
        guard case .notifierFailure(.timedOut) = reason else { return XCTFail("Expected bounded activation timeout") }
        try await waitUntil { transport.leases.get().first?.state.get().ended == true }
        XCTAssertEqual(fake.subscriberCount, 0)
        _ = try await client.readConfigStatus()
    }

    func testSlowConsumerReceivesOnlyLatestGenericSnapshot() async throws {
        let (fake, _, client) = try await connected()
        let stream = await client.extensibleLiveSignals()
        var iterator = stream.makeAsyncIterator()
        while let value = await iterator.next() { if case .active = value { break } }
        for sequence: UInt8 in 1...20 {
            fake.notify(.extensibleLiveSignals, Data([1, sequence, 0, 1, 0x78, 0x56, 0x34, 0x12, 5, 1, 0, 1, 9, 1]))
        }
        guard case .active(let latest) = await iterator.next() else { return XCTFail("Expected snapshot") }
        XCTAssertEqual(latest.sequence, 20)
        await client.reset()
    }

    func testWatchdogClearsValuesAtTwoSecondsAndIndependentRecordsExpire() async throws {
        let (fake, _, client) = try await connected()
        let recorder = TelemetryRecorder(await client.extensibleLiveSignals())
        defer { recorder.cancel() }
        _ = try await active(recorder)
        fake.notify(.extensibleLiveSignals, bytes("0100000178563412050100010901"))
        try await waitUntil { if case .active(let s) = recorder.latest { return s.sequence == 0 }; return false }
        try await Task.sleep(for: .milliseconds(2100))
        let stalled = try await active(recorder)
        XCTAssertTrue(stalled.isStalled)
        XCTAssertEqual(stalled.reading(for: "example.enabled"), .unknown)
        // A record expires independently while empty matching packets keep the stream alive.
        fake.notify(.extensibleLiveSignals, bytes("0101000178563412050100010901"))
        for sequence: UInt8 in 2...4 {
            try await Task.sleep(for: .milliseconds(1050))
            fake.notify(.extensibleLiveSignals, Data([1, sequence, 0, 1, 0x78, 0x56, 0x34, 0x12]))
        }
        try await waitUntil { if case .active(let s) = recorder.latest { return s.sequence == 4 }; return false }
        let expired = try await active(recorder)
        XCTAssertFalse(expired.isStalled)
        XCTAssertEqual(expired.reading(for: "example.enabled"), .unknown)
    }

}

private final class NegotiationTransport: CompanionTransport, @unchecked Sendable {
    let fake: FakeController
    let activations = LockedValue<[CompanionCharacteristic]>([])
    let subscriptions = LockedValue<[CompanionCharacteristic]>([])
    let endpoints = LockedValue(Set(CompanionCharacteristic.allCases))
    let catalogReads = LockedValue(0)
    let leases = LockedValue<[NegotiationLease]>([])
    let oldHandlers = LockedValue<[@Sendable (Data) -> Void]>([])
    var activationError: CompanionTransportError?
    var activationDelay: Duration?
    var endBeforeReturningLease = false
    init(_ fake: FakeController) { self.fake = fake }
    func read(_ characteristic: CompanionCharacteristic) async throws -> Data {
        if characteristic == .signalCatalog { catalogReads.withValue { $0 += 1 } }
        return try await fake.read(characteristic)
    }
    func write(_ value: Data, to characteristic: CompanionCharacteristic) async throws { try await fake.write(value, to: characteristic) }
    func maximumWriteLength() async throws -> Int { try await fake.maximumWriteLength() }
    func availableCharacteristics() async throws -> Set<CompanionCharacteristic> { endpoints.get() }
    func activateLiveNotifier(_ characteristic: CompanionCharacteristic) async throws -> CompanionSubscription {
        activations.withValue { $0.append(characteristic) }
        if let activationError { throw activationError }
        if let activationDelay { await Task.detached { try? await Task.sleep(for: activationDelay) }.value }
        let lease = NegotiationLease()
        leases.withValue { $0.append(lease) }
        if endBeforeReturningLease { lease.cancel() }
        return lease
    }
    func subscribe(to characteristic: CompanionCharacteristic, handler: @escaping @Sendable (Data) -> Void) -> CompanionSubscription {
        subscriptions.withValue { $0.append(characteristic) }
        if characteristic == .extensibleLiveSignals { oldHandlers.withValue { $0.append(handler) } }
        return fake.subscribe(to: characteristic, handler: handler)
    }
}

private final class NegotiationLease: CompanionSubscription, @unchecked Sendable {
    let state = LockedValue((ended: false, handler: Optional<@Sendable () -> Void>.none))
    func cancel() {
        let handler = state.withValue { value -> (@Sendable () -> Void)? in
            guard !value.ended else { return nil }
            value.ended = true
            defer { value.handler = nil }
            return value.handler
        }
        handler?()
    }
    func onTermination(_ handler: @escaping @Sendable () -> Void) {
        let ended = state.withValue { value -> Bool in
            if value.ended { return true }
            value.handler = handler
            return false
        }
        if ended { handler() }
    }
}

private struct TestTimeout: Error {}

private final class TelemetryRecorder: @unchecked Sendable {
    let values = LockedValue<[CompanionLiveTelemetryState]>([])
    var latest: CompanionLiveTelemetryState? { values.get().last }
    let task: Task<Void, Never>
    init(_ stream: AsyncStream<CompanionLiveTelemetryState>) {
        let values = values
        task = Task { for await value in stream { values.withValue { $0.append(value) } } }
    }
    func cancel() { task.cancel() }
}
