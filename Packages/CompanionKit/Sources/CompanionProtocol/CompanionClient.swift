import Foundation

/// A step of a client operation, used to say where a failure happened.
public enum CompanionOperationStep: Equatable, Sendable {
    case readDeviceInfo
    case readConfigStatus
    case readConfig
    case abort
    case start
    case chunk
    case commit
    case command
}

/// Why a client operation failed.
public enum CompanionClientError: Error, Equatable, Sendable {
    /// Device info has not been read on this connection. It must be read first.
    case deviceInfoNotRead
    /// The controller speaks a protocol major version this app does not
    /// support. The app or the firmware needs an update.
    case unsupportedProtocol(major: UInt8)
    /// The controller's live signals layout is not one this app decodes.
    case unsupportedLiveSignalLayout(UInt8)
    /// The document's `version` is not the controller's config schema version.
    case configSchemaMismatch(document: Int, controller: UInt16)
    /// The document is not JSON with an integer top-level `version`.
    case unreadableDocumentVersion
    case emptyDocument
    case documentTooLarge(size: Int, maximum: Int)
    /// The link's MTU is below the 64 bytes a config transfer needs.
    case mtuTooSmall(maximumWriteLength: Int)
    /// Another upload is running on this client.
    case uploadInProgress
    /// The controller did not answer in time.
    case timedOut(CompanionOperationStep)
    /// The controller answered with an error response.
    case controllerError(ATTError, step: CompanionOperationStep)
    /// The controller's loader rejected the document.
    case configRejected(ConfigRejection)
    /// The controller's dry-run apply rejected the document.
    case applyRejected(ApplyRejection)
    /// The commit could not be saved. The config the controller loads at its
    /// next boot is uncertain: upload again or revert to factory now.
    case storageFailed
    /// The received bytes did not match the CRC; the transfer was discarded.
    case checksumMismatch
    /// The link dropped or timed out during commit. Reconnect, read Config
    /// status and compare it with the receipt, or upload again.
    case commitOutcomeUnknown
    /// The link dropped before the controller answered the command.
    /// Reconnect and re-read state.
    case commandOutcomeUnknown(CompanionCommand)
    /// Config read-back pages kept disagreeing, or the document failed its CRC.
    case readBackInconsistent
    case malformed(ProtocolDecodingError)
    case transport(CompanionTransportError)
}

extension CompanionClientError {
    /// The write may have reached the controller but no response came back:
    /// the link dropped, failed in another way, or timed out. Only
    /// `notConnected` means the write never left the phone.
    var isUnknownWriteOutcome: Bool {
        switch self {
        case .timedOut, .transport(.disconnected), .transport(.other): true
        default: false
        }
    }
}

/// Upload progress, reported after each accepted chunk.
public struct ConfigUploadProgress: Equatable, Sendable {
    public var sentBytes: Int
    public var totalBytes: Int

    public var fraction: Double {
        totalBytes == 0 ? 0 : Double(sentBytes) / Double(totalBytes)
    }
}

/// What a successful commit reported. The controller restarts after it.
public struct ConfigUploadReceipt: Equatable, Sendable {
    /// Canonical length and CRC from the `Saved` status. Nil when the status
    /// notification did not arrive before the link dropped.
    public var savedLength: UInt16?
    public var savedCRC32: UInt32?
}

/// Typed client for the companion protocol over a `CompanionTransport`.
///
/// Read device info first on each connection; every other operation refuses
/// to run until it has been read and the protocol major is supported.
public actor CompanionClient {
    public struct Timeouts: Sendable {
        /// Any single read or write other than commit.
        public var operation: Duration
        /// Commit runs parse, dry-run apply and an NVS write before it answers.
        public var commit: Duration

        public init(operation: Duration = .seconds(10), commit: Duration = .seconds(30)) {
            self.operation = operation
            self.commit = commit
        }
    }

    /// Smallest write length a config transfer needs (ATT MTU 64).
    public static let minimumTransferWriteLength = 61
    private static let maximumOffsetResyncs = 3
    private static let maximumReadBackAttempts = 3

    public nonisolated let transport: CompanionTransport
    public let timeouts: Timeouts
    /// Device info read on this connection.
    public private(set) var deviceInfo: DeviceInfo?
    private var isUploading = false

    public init(transport: CompanionTransport, timeouts: Timeouts = Timeouts()) {
        self.transport = transport
        self.timeouts = timeouts
    }

    // MARK: - Device info

    /// Reads and remembers device info. Check `compatibility()` on the result
    /// before pairing; an unsupported major is reported, not thrown.
    @discardableResult
    public func readDeviceInfo() async throws -> DeviceInfo {
        let value = try await read(.deviceInfo, step: .readDeviceInfo)
        let info = try decode { try DeviceInfo(decoding: value) }
        deviceInfo = info
        return info
    }

    /// Forgets device info, for example after the link dropped.
    public func reset() {
        deviceInfo = nil
    }

    // MARK: - Config

    public func readConfigStatus() async throws -> ConfigStatus {
        _ = try requireSupportedDevice()
        let value = try await read(.configStatus, step: .readConfigStatus)
        return try decode { try ConfigStatus(decoding: value) }
    }

    /// Reads the active config's canonical JSON page by page and checks it
    /// against its CRC.
    public func readActiveConfig() async throws -> ConfigReadBack {
        _ = try requireSupportedDevice()
        for _ in 0..<Self.maximumReadBackAttempts {
            if let readBack = try await readActiveConfigOnce() {
                return readBack
            }
        }
        throw CompanionClientError.readBackInconsistent
    }

    /// Encodes and uploads a config, then commits it.
    public func uploadConfig(
        _ config: ControllerConfig,
        progress: (@Sendable (ConfigUploadProgress) -> Void)? = nil
    ) async throws -> ConfigUploadReceipt {
        let document: Data
        do {
            document = try config.encodedJSON()
        } catch {
            throw CompanionClientError.malformed(.invalidValue(field: "config"))
        }
        return try await uploadConfig(document: document, progress: progress)
    }

    /// Uploads a config document and commits it.
    ///
    /// On success the controller restarts; keep the receipt and pass it to
    /// `isUploadActive(_:)` after reconnecting. Cancelling the task before
    /// commit aborts the transfer. The commit itself is not cancellable.
    public func uploadConfig(
        document: Data,
        progress: (@Sendable (ConfigUploadProgress) -> Void)? = nil
    ) async throws -> ConfigUploadReceipt {
        let info = try requireSupportedDevice()
        guard !document.isEmpty else { throw CompanionClientError.emptyDocument }
        guard document.count <= Int(info.maxConfigBytes) else {
            throw CompanionClientError.documentTooLarge(size: document.count, maximum: Int(info.maxConfigBytes))
        }
        // Compatibility rule 4: write only a document whose version matches.
        guard let version = Self.documentVersion(document) else {
            throw CompanionClientError.unreadableDocumentVersion
        }
        guard version == Int(info.configSchemaVersion) else {
            throw CompanionClientError.configSchemaMismatch(document: version, controller: info.configSchemaVersion)
        }
        guard !isUploading else { throw CompanionClientError.uploadInProgress }
        isUploading = true
        defer { isUploading = false }

        let maximumWriteLength = try await perform(.start, timeout: timeouts.operation) {
            try await self.transport.maximumWriteLength()
        }
        guard maximumWriteLength >= Self.minimumTransferWriteLength else {
            throw CompanionClientError.mtuTooSmall(maximumWriteLength: maximumWriteLength)
        }
        let chunkLength = maximumWriteLength - ConfigWritePDU.chunkHeaderLength

        let latestStatus = LockedValue<ConfigStatus?>(nil)
        let subscription = transport.subscribe(to: .configStatus) { value in
            if let status = try? ConfigStatus(decoding: value) {
                latestStatus.set(status)
            }
        }
        defer { subscription.cancel() }

        let bytes = [UInt8](document)
        let total = bytes.count
        do {
            try await writeConfig(.abort, step: .abort)
            try await writeConfig(.start(totalLength: UInt16(total), crc32: CRC32.checksum(bytes)), step: .start)
            progress?(ConfigUploadProgress(sentBytes: 0, totalBytes: total))

            var offset = 0
            var resyncs = 0
            while offset < total {
                try Task.checkCancellation()
                let end = min(offset + chunkLength, total)
                do {
                    try await writeConfig(.chunk(offset: UInt16(offset), data: Data(bytes[offset..<end])), step: .chunk)
                    offset = end
                    progress?(ConfigUploadProgress(sentBytes: offset, totalBytes: total))
                } catch CompanionClientError.controllerError(.known(.offsetMismatch), let step)
                    where resyncs < Self.maximumOffsetResyncs {
                    // Resume from what the controller actually holds.
                    resyncs += 1
                    let status = try await readConfigStatus()
                    guard status.state == .known(.receiving),
                          Int(status.transferLength) == total,
                          Int(status.receivedLength) <= total
                    else {
                        throw CompanionClientError.controllerError(.known(.offsetMismatch), step: step)
                    }
                    offset = Int(status.receivedLength)
                }
            }
            try Task.checkCancellation()
        } catch {
            // Leave nothing open on the controller; its idle timeout is the backstop.
            try? await perform(.abort, timeout: timeouts.operation, cancellable: false) {
                try await self.transport.write(ConfigWritePDU.abort.encoded, to: .config)
            }
            throw error
        }

        do {
            try await perform(.commit, timeout: timeouts.commit, cancellable: false) {
                try await self.transport.write(ConfigWritePDU.commit.encoded, to: .config)
            }
        } catch let error as CompanionClientError {
            throw await commitFailure(error, latestStatus: latestStatus.get())
        }

        // The controller notifies `Saved` before it answers the commit.
        let saved = latestStatus.get().flatMap { $0.result == .known(.saved) ? $0 : nil }
        return ConfigUploadReceipt(savedLength: saved?.savedLength, savedCRC32: saved?.savedCRC32)
    }

    /// After the controller restarted and the link is back (and device info
    /// was read again), checks that the uploaded config is the one running.
    public func isUploadActive(_ receipt: ConfigUploadReceipt) async throws -> Bool {
        guard let crc = receipt.savedCRC32 else { return false }
        return try await readConfigStatus().isActive(savedCRC32: crc)
    }

    // MARK: - Commands

    /// Sends a command. Both commands end the connection; a drop before the
    /// response is an unknown outcome, so reconnect and re-read state.
    public func send(_ command: CompanionCommand) async throws {
        _ = try requireSupportedDevice()
        do {
            try await perform(.command, timeout: timeouts.operation, cancellable: false) {
                try await self.transport.write(command.encoded, to: .command)
            }
        } catch let error as CompanionClientError where error.isUnknownWriteOutcome {
            throw CompanionClientError.commandOutcomeUnknown(command)
        }
    }

    // MARK: - Live signals

    /// Live signals frames, starting with an all-unknown frame. Whenever no
    /// frame arrives for `stallTimeout`, the stream yields an all-unknown
    /// frame, so a stalled link never shows its last values as current.
    /// The stream ends when the consumer stops iterating.
    public func liveSignals(
        stallTimeout: Duration = LiveSignalFeed.defaultStallTimeout
    ) throws -> AsyncStream<LiveSignalFrame> {
        let info = try requireSupportedDevice()
        guard info.compatibility().canDecodeLiveSignals else {
            throw CompanionClientError.unsupportedLiveSignalLayout(info.liveSignalLayoutVersion)
        }
        let transport = transport
        // Keep only the newest value: a slow consumer sees current frames, not a backlog.
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let clock = ContinuousClock()
            let feed = LockedValue((feed: LiveSignalFeed(stallTimeout: stallTimeout), reportedStall: true))
            continuation.yield(.unknown)

            let subscription = transport.subscribe(to: .liveSignals) { value in
                let frame = feed.withValue { state -> LiveSignalFrame? in
                    guard let frame = state.feed.receive(value, at: clock.now) else { return nil }
                    state.reportedStall = false
                    return frame
                }
                if let frame { continuation.yield(frame) }
            }
            let watchdog = Task {
                while !Task.isCancelled {
                    // Sleep to the exact stall deadline; poll only while none is armed.
                    let deadline = feed.withValue { $0.reportedStall ? nil : $0.feed.stallDeadline }
                    if let deadline {
                        try? await Task.sleep(until: deadline, clock: .continuous)
                    } else {
                        try? await Task.sleep(for: stallTimeout / 4)
                    }
                    let stalled = feed.withValue { state -> Bool in
                        guard !state.reportedStall, state.feed.isStalled(at: clock.now) else { return false }
                        state.reportedStall = true
                        return true
                    }
                    if stalled { continuation.yield(.unknown) }
                }
            }
            continuation.onTermination = { _ in
                subscription.cancel()
                watchdog.cancel()
            }
        }
    }

    // MARK: - Helpers

    private func requireSupportedDevice() throws -> DeviceInfo {
        guard let info = deviceInfo else { throw CompanionClientError.deviceInfoNotRead }
        guard info.compatibility().isProtocolSupported else {
            throw CompanionClientError.unsupportedProtocol(major: info.protocolMajor)
        }
        return info
    }

    /// The document's top-level integer `version`, if it parses.
    private static func documentVersion(_ document: Data) -> Int? {
        struct Header: Decodable { let version: Int }
        return try? JSONDecoder().decode(Header.self, from: document).version
    }

    private func readActiveConfigOnce() async throws -> ConfigReadBack? {
        var first: ConfigReadPage?
        var document = Data()
        var offset: UInt16 = 0
        repeat {
            try await writeConfig(.selectReadPage(offset: offset), step: .readConfig)
            let value = try await read(.config, step: .readConfig)
            let page = try decode { try ConfigReadPage(decoding: value) }
            if let first {
                guard page.source == first.source,
                      page.totalLength == first.totalLength,
                      page.crc32 == first.crc32
                else { return nil }
            } else {
                first = page
            }
            guard page.pageOffset == offset, !(page.data.isEmpty && offset < page.totalLength) else { return nil }
            document.append(page.data)
            offset += UInt16(page.data.count)
        } while offset < first!.totalLength

        guard let first, CRC32.checksum(document) == first.crc32 else { return nil }
        return ConfigReadBack(source: first.source, document: document, crc32: first.crc32)
    }

    private func commitFailure(_ error: CompanionClientError, latestStatus: ConfigStatus?) async -> CompanionClientError {
        guard case .controllerError(let code, _) = error else {
            return error.isUnknownWriteOutcome ? .commitOutcomeUnknown : error
        }
        switch code {
        case .known(.configRejected):
            let status = await statusAfterCommit(latestStatus, expecting: .configRejected)
            return status?.rejection.map(CompanionClientError.configRejected) ?? error
        case .known(.applyRejected):
            let status = await statusAfterCommit(latestStatus, expecting: .applyRejected)
            return status?.applyRejection.map(CompanionClientError.applyRejected) ?? error
        case .known(.storageFailure):
            return .storageFailed
        case .known(.checksumMismatch):
            return .checksumMismatch
        default:
            return error
        }
    }

    /// The notified status if it carries `result`, otherwise a fresh read.
    private func statusAfterCommit(_ notified: ConfigStatus?, expecting result: ConfigStatus.ResultCode) async -> ConfigStatus? {
        if let notified, notified.result == .known(result) { return notified }
        return try? await readConfigStatus()
    }

    private func writeConfig(_ pdu: ConfigWritePDU, step: CompanionOperationStep) async throws {
        try await perform(step, timeout: timeouts.operation) {
            try await self.transport.write(pdu.encoded, to: .config)
        }
    }

    private func read(_ characteristic: CompanionCharacteristic, step: CompanionOperationStep) async throws -> Data {
        try await perform(step, timeout: timeouts.operation) {
            try await self.transport.read(characteristic)
        }
    }

    private func decode<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ProtocolDecodingError {
            throw CompanionClientError.malformed(error)
        }
    }

    /// Runs a transport call with a timeout and maps its errors.
    private func perform<T: Sendable>(
        _ step: CompanionOperationStep,
        timeout: Duration,
        cancellable: Bool = true,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await withTimeout(timeout, cancellable: cancellable, operation)
        } catch is OperationTimedOut {
            throw CompanionClientError.timedOut(step)
        } catch let error as CompanionTransportError {
            if case .att(let code) = error {
                throw CompanionClientError.controllerError(code, step: step)
            }
            throw CompanionClientError.transport(error)
        }
    }
}

// MARK: - Concurrency helpers

private struct OperationTimedOut: Error {}

/// A value guarded by a lock, shared with transport callbacks.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        withValue { $0 = newValue }
    }

    func withValue<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// Races `operation` against a timer. Unlike a task group, it returns as soon
/// as the timer fires, even when the transport call ignores cancellation.
private func withTimeout<T: Sendable>(
    _ timeout: Duration,
    cancellable: Bool,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let resumed = LockedValue(false)
    let tasks = LockedValue<[Task<Void, Never>]>([])
    @Sendable func finish(_ continuation: CheckedContinuation<T, Error>, _ result: Result<T, Error>) {
        let first = resumed.withValue { done -> Bool in
            defer { done = true }
            return !done
        }
        guard first else { return }
        tasks.get().forEach { $0.cancel() }
        continuation.resume(with: result)
    }
    let race = { @Sendable (continuation: CheckedContinuation<T, Error>) in
        let work = Task {
            do {
                finish(continuation, .success(try await operation()))
            } catch {
                finish(continuation, .failure(error))
            }
        }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { finish(continuation, .failure(OperationTimedOut())) }
        }
        tasks.set([work, timer])
        if resumed.get() { work.cancel(); timer.cancel() }
    }
    guard cancellable else {
        return try await withCheckedThrowingContinuation(race)
    }
    let pending = LockedValue<CheckedContinuation<T, Error>?>(nil)
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            pending.set(continuation)
            race(continuation)
            if Task.isCancelled { finish(continuation, .failure(CancellationError())) }
        }
    } onCancel: {
        if let continuation = pending.get() {
            finish(continuation, .failure(CancellationError()))
        }
    }
}
