import Foundation
import Observation
import CompanionProtocol

/// Negotiated live signals for curated dashboards and generic consumers.
/// Run from the screen's task while the controller session is ready.
@MainActor
@Observable
public final class LiveTelemetry {
    public private(set) var frame: LiveSignalFrame = .unknown
    /// Complete metadata and readings, including unfamiliar semantic keys.
    public private(set) var snapshot: ExtensibleSignalSnapshot?
    public var catalog: SignalCatalog? { snapshot?.catalog }
    public var readings: [ExtensibleSignalState] { snapshot?.signals ?? [] }
    /// Observed packet sequences in the last second, excluding watchdog updates.
    public private(set) var framesPerSecond = 0
    public private(set) var failure: String?
    public private(set) var unavailableReason: CompanionLiveTelemetryUnavailableReason?

    @ObservationIgnored private let session: ControllerSession
    @ObservationIgnored private var arrivals: [ContinuousClock.Instant] = []
    @ObservationIgnored private var lastSequence: UInt16?
    @ObservationIgnored private var lastToken: UInt32?
    @ObservationIgnored private let clock = ContinuousClock()

    public init(session: ControllerSession) {
        self.session = session
    }

    public func run() async {
        clear()
        failure = nil
        unavailableReason = nil
        defer { clear() }
        guard session.phase == .ready else { return }
        let stream = await session.client.extensibleLiveSignals()
        for await next in stream {
            guard !Task.isCancelled else { break }
            receive(next, at: clock.now)
        }
    }

    func receive(_ next: CompanionLiveTelemetryState, at now: ContinuousClock.Instant) {
        switch next {
        case .discovering:
            clear()
            failure = nil
            unavailableReason = nil
        case .unavailable(let reason):
            clear()
            unavailableReason = reason
            failure = switch reason {
            case .capabilityUnavailable:
                "This controller does not support extensible live signals."
            case .missingEndpoints:
                "This controller's live signal endpoints are not available."
            case .catalogFailure:
                "The controller's signal catalog could not be read."
            case .notifierEnded:
                "Live signals stopped. The controller connection is still available."
            case .connectionEnded:
                "Live signals stopped because the controller disconnected."
            case .deviceUnavailable, .notifierFailure:
                "Live signals are not available."
            }
        case .active(let snapshot):
            failure = nil
            unavailableReason = nil
            self.snapshot = snapshot
            frame = LiveSignalProjection.frame(from: snapshot)
            // Expiry snapshots retain the same full-width sequence. Rediscovery
            // clears this identity, so a restarted sequence counts once again.
            if !snapshot.isStalled, let sequence = snapshot.sequence,
               sequence != lastSequence || snapshot.catalog?.token != lastToken {
                arrivals.append(now)
                lastSequence = sequence
                lastToken = snapshot.catalog?.token
            }
            arrivals.removeAll { now - $0 > .seconds(1) }
            framesPerSecond = snapshot.isStalled ? 0 : arrivals.count
        }
    }

    private func clear() {
        snapshot = nil
        frame = .unknown
        arrivals.removeAll()
        lastSequence = nil
        lastToken = nil
        framesPerSecond = 0
    }
}
