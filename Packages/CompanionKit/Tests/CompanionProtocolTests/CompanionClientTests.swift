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
            protocolMajor: 1, protocolMinor: 0, configSchemaVersion: 2, liveSignalLayoutVersion: 2,
            flags: 0, maxConfigBytes: 4096, firmwareVersion: "", hardwareID: ""
        )
        XCTAssertEqual(info.compatibility(), Compatibility(
            isProtocolSupported: true, hasNewerMinor: false, canEditConfig: false, canDecodeLiveSignals: false
        ))
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
        controller.deviceInfo.liveSignalLayoutVersion = 2
        try await connect()
        await assertThrows(.unsupportedLiveSignalLayout(2)) { try await self.client.liveSignals() }
        XCTAssertEqual(controller.subscriberCount, 0)
    }
}
