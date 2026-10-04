import Foundation
@testable import CompanionProtocol

/// An in-memory controller that follows the config transfer spec closely
/// enough to drive `CompanionClient` through its success and error paths.
final class FakeController: CompanionTransport, @unchecked Sendable {
    enum CommitOutcome {
        case save
        case reject(category: UInt8, code: UInt8, validation: UInt8, index: UInt16, path: String)
        case applyReject(stage: UInt8, section: UInt8, index: UInt16, engine: UInt8)
        case storageFailure
        case dropLink
    }

    private let lock = NSLock()

    // Device and link.
    var deviceInfo = DeviceInfo(
        protocolMajor: 1, protocolMinor: 0, configSchemaVersion: 1, liveSignalLayoutVersion: 1,
        flags: 0, maxConfigBytes: 4096, firmwareVersion: "v1.0.0", hardwareID: "weact-can485-v1.1"
    )
    var maximumWrite = 244
    var isConnected = true

    // Config transfer state.
    var state: UInt8 = 0
    var result: UInt8 = 0
    var buffer = Data()
    var transferLength = 0
    var transferCRC: UInt32 = 0
    var savedLength = 0
    var savedCRC: UInt32 = 0
    var rejection: (category: UInt8, code: UInt8, validation: UInt8, index: UInt16, path: String)?
    var applyRejection: (stage: UInt8, section: UInt8, index: UInt16, engine: UInt8)?
    var commitOutcome = CommitOutcome.save

    // Active config read-back.
    var activeSource: UInt8 = 0
    var activeDocument = Data()
    var readPageOffset = 0

    // Fault injection.
    /// Called before each write is handled; may change state or throw.
    var beforeWrite: ((FakeController, CompanionCharacteristic, Data) throws -> Void)?
    /// Called before each read; may change state.
    var beforeRead: ((FakeController, CompanionCharacteristic) -> Void)?
    /// Writes to these characteristics never complete.
    var hangingWrites: Set<CompanionCharacteristic> = []
    /// Delay before every write completes.
    var writeDelay: Duration?

    // Observation.
    private(set) var writes: [(CompanionCharacteristic, Data)] = []
    private var subscribers: [CompanionCharacteristic: [UUID: @Sendable (Data) -> Void]] = [:]

    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var configWrites: [Data] { withLock { writes.filter { $0.0 == .config }.map(\.1) } }
    var commandWrites: [Data] { withLock { writes.filter { $0.0 == .command }.map(\.1) } }
    var subscriberCount: Int { withLock { subscribers.values.map(\.count).reduce(0, +) } }

    // MARK: CompanionTransport

    func read(_ characteristic: CompanionCharacteristic) async throws -> Data {
        try withLock {
            guard isConnected else { throw CompanionTransportError.notConnected }
            beforeRead?(self, characteristic)
            switch characteristic {
            case .deviceInfo: return Self.encode(deviceInfo)
            case .configStatus: return statusValue()
            case .config: return readPage()
            case .liveSignals, .command: throw CompanionTransportError.att(.unknown(0x02))
            }
        }
    }

    func write(_ value: Data, to characteristic: CompanionCharacteristic) async throws {
        let hangs = withLock {
            writes.append((characteristic, value))
            return hangingWrites.contains(characteristic)
        }
        if let writeDelay { try await Task.sleep(for: writeDelay) }
        if hangs { try await Task.sleep(for: .seconds(3600)) }
        var notifications: [Data] = []
        let error: Error? = withLock {
            guard isConnected else { return CompanionTransportError.notConnected }
            do {
                try beforeWrite?(self, characteristic, value)
                let before = (state, result)
                switch characteristic {
                case .config: try handleConfig(value)
                case .command: try handleCommand(value)
                default: throw CompanionTransportError.att(.unknown(0x03))
                }
                if before != (state, result) { notifications.append(statusValue()) }
                return nil
            } catch {
                return error
            }
        }
        // The controller notifies before it answers the write.
        notifications.forEach { notify(.configStatus, $0) }
        if case .dropLink = withLock({ commitOutcome }), value == ConfigWritePDU.commit.encoded {
            withLock { isConnected = false }
            throw CompanionTransportError.disconnected
        }
        if let error { throw error }
    }

    func maximumWriteLength() async throws -> Int {
        withLock { maximumWrite }
    }

    func subscribe(
        to characteristic: CompanionCharacteristic,
        handler: @escaping @Sendable (Data) -> Void
    ) -> CompanionSubscription {
        let id = UUID()
        withLock { subscribers[characteristic, default: [:]][id] = handler }
        return Subscription { [weak self] in
            self?.withLock { _ = self?.subscribers[characteristic]?.removeValue(forKey: id) }
        }
    }

    func notify(_ characteristic: CompanionCharacteristic, _ value: Data) {
        let handlers = withLock { Array((subscribers[characteristic] ?? [:]).values) }
        handlers.forEach { $0(value) }
    }

    // MARK: Controller behaviour

    private func att(_ code: ATTErrorCode) -> CompanionTransportError {
        .att(.known(code))
    }

    private func handleConfig(_ value: Data) throws {
        let bytes = [UInt8](value)
        guard let opcode = bytes.first else { throw att(.invalidAttributeValueLength) }
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        switch opcode {
        case 0x01:
            guard bytes.count == 7 else { throw att(.invalidAttributeValueLength) }
            guard maximumWrite + 3 >= 64 else { throw att(.mtuTooSmall) }
            let length = u16(1)
            guard length > 0 else { throw att(.invalidPDU) }
            guard length <= Int(deviceInfo.maxConfigBytes) else { throw att(.tooLarge) }
            guard state != 1 else { throw att(.busy) }
            transferLength = length
            transferCRC = bytes[3..<7].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
            buffer = Data()
            state = 1
            result = 0
            rejection = nil
            applyRejection = nil
        case 0x02:
            guard bytes.count >= 4, bytes.count <= maximumWrite else { throw att(.invalidAttributeValueLength) }
            guard state == 1 else { throw att(.invalidState) }
            guard u16(1) == buffer.count else { throw att(.offsetMismatch) }
            guard buffer.count + bytes.count - 3 <= transferLength else { throw att(.invalidPDU) }
            buffer.append(contentsOf: bytes[3...])
        case 0x03:
            guard bytes.count == 1 else { throw att(.invalidAttributeValueLength) }
            guard state == 1 else { throw att(.invalidState) }
            guard buffer.count == transferLength else { throw att(.incomplete) }
            guard CRC32.checksum(buffer) == transferCRC else {
                discard(result: 7)
                throw att(.checksumMismatch)
            }
            switch commitOutcome {
            case .save, .dropLink:
                savedLength = buffer.count
                savedCRC = transferCRC
                buffer = Data()
                state = 2
                result = 1
            case .reject(let category, let code, let validation, let index, let path):
                rejection = (category, code, validation, index, path)
                discard(result: 2)
                throw att(.configRejected)
            case .applyReject(let stage, let section, let index, let engine):
                applyRejection = (stage, section, index, engine)
                discard(result: 3)
                throw att(.applyRejected)
            case .storageFailure:
                discard(result: 4)
                throw att(.storageFailure)
            }
        case 0x04:
            guard bytes.count == 1 else { throw att(.invalidAttributeValueLength) }
            if state == 1 { discard(result: 5) }
        case 0x05:
            guard bytes.count == 3 else { throw att(.invalidAttributeValueLength) }
            guard u16(1) <= activeDocument.count else { throw att(.invalidPDU) }
            readPageOffset = u16(1)
        default:
            throw att(.unsupportedOperation)
        }
    }

    private func discard(result newResult: UInt8) {
        state = 0
        result = newResult
        buffer = Data()
    }

    private func handleCommand(_ value: Data) throws {
        let bytes = [UInt8](value)
        guard bytes.count == 2 else { throw att(.invalidAttributeValueLength) }
        guard bytes[1] == bytes[0] ^ 0xFF else { throw att(.invalidPDU) }
        guard bytes[0] == 1 || bytes[0] == 2 else { throw att(.unsupportedOperation) }
        guard state != 1 else { throw att(.busy) }
    }

    private func readPage() -> Data {
        var page = Data([activeSource])
        page.appendLittleEndian(UInt16(activeDocument.count))
        page.appendLittleEndian(activeDocument.isEmpty ? 0 : CRC32.checksum(activeDocument))
        page.appendLittleEndian(UInt16(readPageOffset))
        let end = min(activeDocument.count, readPageOffset + 200)
        page.append(activeDocument[readPageOffset..<end])
        return page
    }

    func statusValue() -> Data {
        var value = Data([state, result, 0, activeSource])
        value.appendLittleEndian(UInt16(activeDocument.count))
        value.appendLittleEndian(activeDocument.isEmpty ? 0 : CRC32.checksum(activeDocument))
        value.appendLittleEndian(UInt16(state == 1 ? transferLength : 0))
        value.appendLittleEndian(UInt16(state == 1 ? buffer.count : 0))
        value.appendLittleEndian(UInt16(result == 1 ? savedLength : 0))
        value.appendLittleEndian(result == 1 ? savedCRC : 0)
        let reject = result == 2 ? rejection : nil
        value.append(contentsOf: [reject?.category ?? 0, reject?.code ?? 0, reject?.validation ?? 0])
        value.appendLittleEndian(reject?.index ?? 0)
        let apply = result == 3 ? applyRejection : nil
        value.append(contentsOf: [apply?.stage ?? 0, 0, apply?.section ?? 0])
        value.appendLittleEndian(apply?.index ?? 0)
        value.append(contentsOf: [0, apply?.engine ?? 0, 0, 0])
        let path = Data((reject?.path ?? "").utf8)
        value.append(UInt8(path.count))
        value.append(path)
        return value
    }

    static func encode(_ info: DeviceInfo) -> Data {
        var value = Data([info.protocolMajor, info.protocolMinor])
        value.appendLittleEndian(info.configSchemaVersion)
        value.append(contentsOf: [info.liveSignalLayoutVersion, info.flags])
        value.appendLittleEndian(info.maxConfigBytes)
        for string in [info.firmwareVersion, info.hardwareID] {
            value.append(UInt8(string.utf8.count))
            value.append(contentsOf: string.utf8)
        }
        return value
    }
}

private struct Subscription: CompanionSubscription {
    let onCancel: @Sendable () -> Void
    func cancel() { onCancel() }
}
