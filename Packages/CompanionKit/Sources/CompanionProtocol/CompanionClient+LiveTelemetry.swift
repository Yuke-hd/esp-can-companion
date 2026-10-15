import Foundation

/// Negotiated telemetry is unavailable until both endpoints and a complete
/// catalog are usable. This path never selects the fixed-layout notifier.
public enum CompanionLiveTelemetryState: Equatable, Sendable {
    case discovering
    case unavailable(CompanionLiveTelemetryUnavailableReason)
    case active(ExtensibleSignalSnapshot)
}

public enum CompanionLiveTelemetryUnavailableReason: Equatable, Sendable {
    case deviceUnavailable(CompanionClientError)
    case capabilityUnavailable
    case missingEndpoints
    case catalogFailure(CompanionClientError)
    case notifierFailure(CompanionClientError)
    case notifierEnded
    case connectionEnded
}

extension CompanionClient {
    /// Shares one catalog/selected notifier across consumers, retaining only
    /// the latest state for each. Cancelling the final consumer clears readings
    /// and disables the notifier; the immutable connection catalog is retained.
    /// Reset clears the catalog. Remote notifier loss ends these streams while
    /// preserving connection/configuration state and its immutable catalog.
    public func extensibleLiveSignals() -> AsyncStream<CompanionLiveTelemetryState> {
        let session: ExtensibleTelemetrySession
        if let existing = extensibleTelemetrySession, !existing.isClosed {
            session = existing
        } else {
            // A cancelled consumer may have observed a token change before
            // its rediscovery actor hop. Never restart against that old map.
            if let token = extensibleTelemetrySession?.unexpectedToken {
                invalidateSignalCatalog(ifTokenDiffersFrom: token)
            }
            session = ExtensibleTelemetrySession()
            extensibleTelemetrySession = session
            session.operation = Task { await self.startExtensibleTelemetry(session) }
        }
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            session.add(id, continuation)
            continuation.onTermination = { [weak self] _ in
                if session.remove(id) {
                    Task { await self?.stopExtensibleTelemetry(session) }
                }
            }
        }
    }

    private func startExtensibleTelemetry(_ session: ExtensibleTelemetrySession) async {
        do {
            let info: DeviceInfo
            do { info = try requireSupportedDevice() }
            catch { return failTelemetry(session, .deviceUnavailable(Self.telemetryError(error))) }
            guard info.supportsExtensibleLiveSignals else { return failTelemetry(session, .capabilityUnavailable) }
            let endpoints = try await perform(.readSignalCatalog, timeout: timeouts.operation) {
                try await self.transport.availableCharacteristics()
            }
            guard isCurrentTelemetry(session) else { return }
            guard endpoints.contains(.signalCatalog), endpoints.contains(.extensibleLiveSignals) else {
                return failTelemetry(session, .missingEndpoints)
            }
            let catalog: SignalCatalog
            do { catalog = try await discoverSignalCatalog() }
            catch { return failTelemetry(session, .catalogFailure(Self.telemetryError(error))) }
            guard isCurrentTelemetry(session), session.install(catalog) else { return }
            session.subscription = transport.subscribe(to: .extensibleLiveSignals) { [weak self] data in
                if let token = session.receive(data) {
                    Task { await self?.rediscoverTelemetry(session, unexpectedToken: token) }
                }
            }
            // The work may ignore task cancellation. Dispose a late lease in
            // the underlying operation too, not just after the bounded wait.
            let lease = try await perform(.readSignalCatalog, timeout: timeouts.operation) {
                let lease = try await self.transport.activateLiveNotifier(.extensibleLiveSignals)
                if session.isClosed { lease.cancel() }
                return lease
            }
            guard isCurrentTelemetry(session) else { lease.cancel(); return }
            session.lease = lease
            lease.onTermination { [weak self] in
                session.close(.notifierEnded)
                Task { await self?.telemetryNotifierEnded(session) }
            }
            guard session.activate() else { return }
            session.watchdog = Task {
                while !Task.isCancelled && !session.isClosed {
                    if let deadline = session.refreshLiveness() {
                        try? await Task.sleep(until: deadline, clock: .continuous)
                    } else {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            }
        } catch {
            failTelemetry(session, .notifierFailure(Self.telemetryError(error)))
        }
    }

    private func rediscoverTelemetry(_ session: ExtensibleTelemetrySession, unexpectedToken: UInt32) async {
        guard isCurrentTelemetry(session) else { return }
        invalidateSignalCatalog(ifTokenDiffersFrom: unexpectedToken)
        do {
            let catalog = try await discoverSignalCatalog()
            guard isCurrentTelemetry(session), session.install(catalog) else { return }
            _ = session.activate()
        } catch {
            failTelemetry(session, .catalogFailure(Self.telemetryError(error)))
        }
    }

    private func telemetryNotifierEnded(_ session: ExtensibleTelemetrySession) {
        guard extensibleTelemetrySession === session else { return }
        // CCCD loss does not itself prove the connection ended. The session
        // owner calls reset for an actual disconnect; config remains usable.
        stopExtensibleTelemetry(session)
    }

    private func isCurrentTelemetry(_ session: ExtensibleTelemetrySession) -> Bool {
        extensibleTelemetrySession === session && !session.isClosed && !Task.isCancelled
    }

    private func failTelemetry(_ session: ExtensibleTelemetrySession, _ reason: CompanionLiveTelemetryUnavailableReason) {
        guard extensibleTelemetrySession === session else { return }
        session.close(reason)
        stopExtensibleTelemetry(session)
    }

    func stopExtensibleTelemetry(_ session: ExtensibleTelemetrySession) {
        if extensibleTelemetrySession === session {
            if let token = session.unexpectedToken { invalidateSignalCatalog(ifTokenDiffersFrom: token) }
            extensibleTelemetrySession = nil
        }
        session.close(.connectionEnded)
        session.operation?.cancel()
        session.watchdog?.cancel()
        session.subscription?.cancel()
        session.lease?.cancel()
    }

    private static func telemetryError(_ error: Error) -> CompanionClientError {
        if let error = error as? CompanionClientError { return error }
        if let error = error as? CompanionTransportError { return .transport(error) }
        return .transport(.other(String(describing: error)))
    }
}

/// Transport callbacks mutate and publish under one lock so a mismatched token
/// or ended lease clears displayed state immediately, before an actor hop.
final class ExtensibleTelemetrySession: @unchecked Sendable {
    private struct State {
        var feed = ExtensibleSignalFeed()
        var latest: CompanionLiveTelemetryState = .discovering
        var continuations: [UUID: AsyncStream<CompanionLiveTelemetryState>.Continuation] = [:]
        var closed = false
        var active = false
        var unexpectedToken: UInt32?

        mutating func publish(_ value: CompanionLiveTelemetryState) {
            latest = value
            for continuation in continuations.values { continuation.yield(value) }
        }
    }
    private let state = LockedValue(State())
    // Only the client actor owns these resources.
    var operation: Task<Void, Never>?
    var watchdog: Task<Void, Never>?
    var subscription: CompanionSubscription?
    var lease: CompanionSubscription?
    var isClosed: Bool { state.withValue { $0.closed } }
    var unexpectedToken: UInt32? { state.withValue { $0.unexpectedToken } }

    func add(_ id: UUID, _ continuation: AsyncStream<CompanionLiveTelemetryState>.Continuation) {
        let closed = state.withValue { value -> Bool in
            continuation.yield(value.latest)
            guard !value.closed else { return true }
            value.continuations[id] = continuation
            return false
        }
        if closed { continuation.finish() }
    }

    /// Final cancellation seals callbacks synchronously but preserves the
    /// client's catalog cache for a subsequent consumer on this connection.
    func remove(_ id: UUID) -> Bool {
        state.withValue { value in
            value.continuations.removeValue(forKey: id)
            guard value.continuations.isEmpty, !value.closed else { return false }
            value.closed = true
            value.feed.reset()
            return true
        }
    }

    func close(_ reason: CompanionLiveTelemetryUnavailableReason) {
        let continuations = state.withValue { value -> [AsyncStream<CompanionLiveTelemetryState>.Continuation] in
            guard !value.closed else { return [] }
            value.closed = true
            value.active = false
            value.feed.reset()
            value.publish(.unavailable(reason))
            defer { value.continuations.removeAll() }
            return Array(value.continuations.values)
        }
        continuations.forEach { $0.finish() }
    }

    func install(_ catalog: SignalCatalog) -> Bool {
        state.withValue { value in
            guard !value.closed else { return false }
            value.feed.install(catalog: catalog)
            value.unexpectedToken = nil
            return true
        }
    }

    func activate() -> Bool {
        state.withValue { value in
            guard !value.closed, value.feed.catalog != nil else { return false }
            value.active = true
            value.publish(.active(value.feed.snapshot(at: .now)))
            return true
        }
    }

    func receive(_ data: Data) -> UInt32? {
        state.withValue { value in
            guard !value.closed, value.active, value.feed.catalog != nil else { return nil }
            let packet = value.feed.receive(data, at: .now)
            if value.feed.catalog == nil {
                value.active = false
                value.publish(.discovering)
                let token = data.dropFirst(4).prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
                value.unexpectedToken = token
                return token
            }
            if packet != nil { value.publish(.active(value.feed.snapshot(at: .now))) }
            return nil
        }
    }

    func refreshLiveness() -> ContinuousClock.Instant? {
        state.withValue { value in
            guard !value.closed, value.active, let catalog = value.feed.catalog else { return nil }
            let now = ContinuousClock.now
            let snapshot = CompanionLiveTelemetryState.active(value.feed.snapshot(at: now))
            if snapshot != value.latest { value.publish(snapshot) }
            let deadlines = [value.feed.stallDeadline] + catalog.descriptors.map { value.feed.livenessDeadline(for: $0.handle) }
            return deadlines.compactMap { $0 }.filter { $0 > now }.min()
        }
    }
}
