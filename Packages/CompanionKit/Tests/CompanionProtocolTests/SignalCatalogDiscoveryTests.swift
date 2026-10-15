import Foundation
import XCTest
@testable import CompanionProtocol
import CompanionFakes

final class SignalCatalogDiscoveryTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = Bundle.module.url(forResource: "extensible-live-v1", withExtension: "json", subdirectory: "Fixtures/golden-vectors")!
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let hex = (json["catalog"] as! [String: Any])["document_hex"] as! String
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<end], radix: 16)!)
            index = end
        }
        return data
    }

    private func connected(timeout: Duration = .seconds(1)) async throws -> (FakeController, CompanionClient) {
        let fake = FakeController()
        fake.deviceInfo.protocolMinor = 1
        fake.deviceInfo.extensionVersion = 1
        fake.deviceInfo.extensionFlags = 1
        fake.catalogToken = 0x12345678
        fake.catalogDocument = try fixture()
        let client = CompanionClient(transport: fake, timeouts: .init(operation: timeout))
        try await client.readDeviceInfo()
        return (fake, client)
    }

    func testCanonicalMultipageCatalogCachesCompleteImmutableMap() async throws {
        let (fake, client) = try await connected()
        let catalog = try await client.discoverSignalCatalog()
        XCTAssertEqual(catalog.descriptors.count, 7)
        XCTAssertEqual(catalog.descriptor(for: 2)?.key, "example.acceleration")
        XCTAssertEqual(fake.writes.filter { $0.0 == .signalCatalog }.map(\.1),
                       [try SignalCatalogSelector(token: fake.catalogToken, offset: 200).encoded])
        let reads = fake.reads
        fake.catalogDocument = Data([1, 0, 0])
        let cached = try await client.discoverSignalCatalog()
        XCTAssertEqual(cached, catalog)
        XCTAssertEqual(fake.reads, reads)
    }

    func testSmallPagesSplitTLVsAndConfigSelectorsStayIndependent() async throws {
        let (fake, client) = try await connected()
        fake.catalogPageLength = 11
        fake.activeDocument = Data(repeating: 0x20, count: 503)
        fake.readPageOffset = 400
        fake.state = 1
        fake.buffer = Data([8, 9])
        async let catalog = client.discoverSignalCatalog()
        async let config = client.readActiveConfig()
        let (map, readback) = try await (catalog, config)
        XCTAssertEqual(map.descriptors.count, 7)
        XCTAssertEqual(readback.document, fake.activeDocument)
        XCTAssertEqual(fake.state, 1)
        XCTAssertEqual(fake.buffer, Data([8, 9]))
    }

    func testWrongTokenOffsetTotalAndLengthInstallNoPartialMap() async throws {
        for corruption in 0..<4 {
            let (fake, client) = try await connected()
            fake.beforeRead = { fake, characteristic in
                guard characteristic == .signalCatalog, fake.catalogPageOffset > 0 else { return }
                switch corruption {
                case 0: fake.catalogToken += 1
                case 1: fake.catalogPageOffset -= 1
                case 2: fake.catalogDocument.append(0)
                default: fake.catalogReadOverride = Data([1, 0x78, 0x56, 0x34, 0x12, 0x71, 1, 200, 0, 10, 0])
                }
            }
            do { _ = try await client.discoverSignalCatalog(); XCTFail("Expected rejection") } catch {}
            let installed = await client.signalCatalog
            XCTAssertNil(installed)
        }
    }

    func testFailedDiscoveryExplicitlyRestartsFromZero() async throws {
        let (fake, client) = try await connected()
        fake.beforeWrite = { _, characteristic, _ in
            if characteristic == .signalCatalog { throw CompanionTransportError.disconnected }
        }
        do { _ = try await client.discoverSignalCatalog(); XCTFail("Expected interruption") } catch {}
        fake.beforeWrite = nil
        fake.catalogPageOffset = 200
        let catalog = try await client.discoverSignalCatalog()
        XCTAssertEqual(catalog.descriptors.count, 7)
        XCTAssertTrue(fake.writes.contains { $0.0 == .signalCatalog && $0.1 == (try? SignalCatalogSelector(token: fake.catalogToken, offset: 0).encoded) })
    }

    func testConcurrentDiscoveryUsesOneDownload() async throws {
        let (fake, client) = try await connected()
        fake.writeDelay = .milliseconds(30)
        async let first = client.discoverSignalCatalog()
        async let second = client.discoverSignalCatalog()
        let maps = try await [first, second]
        XCTAssertEqual(maps[0], maps[1])
        XCTAssertEqual(fake.writes.filter { $0.0 == .signalCatalog }.count, 1)
    }

    func testReconnectWithRepeatedTokenDownloadsFreshMapping() async throws {
        let (fake, client) = try await connected()
        _ = try await client.discoverSignalCatalog()
        await client.reset()
        fake.catalogDocument = Data([1, 0, 0])
        fake.catalogPageOffset = 0
        try await client.readDeviceInfo()
        let fresh = try await client.discoverSignalCatalog()
        XCTAssertEqual(fresh.token, fake.catalogToken)
        XCTAssertTrue(fresh.descriptors.isEmpty)
    }

    func testUnexpectedTokenClearsMapUntilExplicitCompleteRediscovery() async throws {
        let (fake, client) = try await connected()
        _ = try await client.discoverSignalCatalog()
        let matching = await client.invalidateSignalCatalog(ifTokenDiffersFrom: fake.catalogToken)
        XCTAssertFalse(matching)
        let changed = await client.invalidateSignalCatalog(ifTokenDiffersFrom: 22)
        XCTAssertTrue(changed)
        let cleared = await client.signalCatalog
        XCTAssertNil(cleared)
        fake.catalogToken = 22
        let replacement = try await client.discoverSignalCatalog()
        XCTAssertEqual(replacement.token, 22)
    }

    func testCancellationAndResetRejectLateResults() async throws {
        for reset in [false, true] {
            let (fake, client) = try await connected()
            fake.readDelay = .milliseconds(100)
            let operation = Task { try await client.discoverSignalCatalog() }
            try await Task.sleep(for: .milliseconds(20))
            if reset { await client.reset() } else { operation.cancel() }
            do { _ = try await operation.value; XCTFail("Expected stale/cancelled operation") }
            catch { XCTAssertTrue(reset ? error as? CompanionClientError == .connectionChanged : error is CancellationError) }
            let installed = await client.signalCatalog
            XCTAssertNil(installed)
        }
    }

    func testResetKeepsUncancellableSelectorQuarantinedAndRejectsItsMap() async throws {
        let (fake, _) = try await connected()
        let transport = DelayedCatalogTransport(fake: fake)
        transport.delay.set(false)
        transport.delayWrites.set(true)
        let client = CompanionClient(transport: transport, timeouts: .init(operation: .milliseconds(40)))
        try await client.readDeviceInfo()
        let old = Task { try await client.discoverSignalCatalog() }
        while transport.catalogWrites.get() == 0 { try await Task.sleep(for: .milliseconds(1)) }
        await client.reset()
        try await client.readDeviceInfo()
        do { _ = try await old.value; XCTFail("Expected timeout") } catch {}
        do { _ = try await client.discoverSignalCatalog(); XCTFail("Expected quarantined lane") }
        catch { XCTAssertEqual(error as? CompanionClientError, .timedOut(.readSignalCatalog)) }
        XCTAssertEqual(transport.catalogWrites.get(), 1)
        let map = await client.signalCatalog
        XCTAssertNil(map)
        try await Task.sleep(for: .milliseconds(160))
        transport.delayWrites.set(false)
        let fresh = try await client.discoverSignalCatalog()
        XCTAssertEqual(fresh.descriptors.count, 7)
    }

    func testHungReadAndSelectorAreBounded() async throws {
        for read in [true, false] {
            let (fake, client) = try await connected(timeout: .milliseconds(40))
            if read { fake.hangingReads = [.signalCatalog] } else { fake.hangingWrites = [.signalCatalog] }
            do { _ = try await client.discoverSignalCatalog(); XCTFail("Expected timeout") }
            catch { XCTAssertEqual(error as? CompanionClientError, .timedOut(.readSignalCatalog)) }
            let installed = await client.signalCatalog
            XCTAssertNil(installed)
        }
    }

    func testUncancellableReadQuarantinesLaneUntilUnderlyingCallSettles() async throws {
        let (fake, _) = try await connected()
        let transport = DelayedCatalogTransport(fake: fake)
        let client = CompanionClient(transport: transport, timeouts: .init(operation: .milliseconds(40)))
        try await client.readDeviceInfo()
        for _ in 0..<2 {
            do { _ = try await client.discoverSignalCatalog(); XCTFail("Expected bounded wait") }
            catch { XCTAssertEqual(error as? CompanionClientError, .timedOut(.readSignalCatalog)) }
        }
        XCTAssertEqual(transport.catalogCalls.get(), 1)
        try await Task.sleep(for: .milliseconds(160))
        transport.delay.set(false)
        let catalog = try await client.discoverSignalCatalog()
        XCTAssertEqual(catalog.descriptors.count, 7)
    }
}

private final class DelayedCatalogTransport: CompanionTransport, @unchecked Sendable {
    let fake: FakeController
    let catalogCalls = LockedValue(0)
    let delay = LockedValue(true)
    let delayWrites = LockedValue(false)
    let catalogWrites = LockedValue(0)
    init(fake: FakeController) { self.fake = fake }
    func read(_ characteristic: CompanionCharacteristic) async throws -> Data {
        if characteristic == .signalCatalog {
            catalogCalls.withValue { $0 += 1 }
            if delay.get() {
                // Detached timer deliberately ignores cancellation of this request.
                await Task.detached { try? await Task.sleep(for: .milliseconds(200)) }.value
            }
        }
        return try await fake.read(characteristic)
    }
    func write(_ value: Data, to characteristic: CompanionCharacteristic) async throws {
        if characteristic == .signalCatalog {
            catalogWrites.withValue { $0 += 1 }
            if delayWrites.get() {
                await Task.detached { try? await Task.sleep(for: .milliseconds(200)) }.value
                // Simulate a transport that also completes its selector despite cancellation.
                try fake.writeImmediately(value, to: characteristic)
                return
            }
        }
        try await fake.write(value, to: characteristic)
    }
    func maximumWriteLength() async throws -> Int { try await fake.maximumWriteLength() }
    func subscribe(to characteristic: CompanionCharacteristic, handler: @escaping @Sendable (Data) -> Void) -> CompanionSubscription {
        fake.subscribe(to: characteristic, handler: handler)
    }
}
