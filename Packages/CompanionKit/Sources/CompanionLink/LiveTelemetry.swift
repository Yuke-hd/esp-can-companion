import Foundation
import Observation
import CompanionProtocol

/// The controller's Live signals for a screen that shows them. Call `run()`
/// from the screen's `.task` while the session is ready; it subscribes until
/// cancelled, then shows every signal as unknown again.
@MainActor
@Observable
public final class LiveTelemetry {
    /// The latest frame, or all unknown before the first one and while the
    /// stream is stalled.
    public private(set) var frame: LiveSignalFrame = .unknown
    /// Frames received in the last second, the rate the draft shows as "10 HZ".
    public private(set) var framesPerSecond = 0
    /// Why the stream could not start, such as an unsupported frame layout.
    public private(set) var failure: String?

    @ObservationIgnored private let session: ControllerSession
    @ObservationIgnored private var arrivals: [ContinuousClock.Instant] = []
    @ObservationIgnored private let clock = ContinuousClock()

    public init(session: ControllerSession) {
        self.session = session
    }

    /// Streams frames until the task is cancelled or the stream ends.
    public func run() async {
        defer { clear() }
        guard session.phase == .ready else { return }
        let stream: AsyncStream<LiveSignalFrame>
        do {
            stream = try await session.client.liveSignals()
            failure = nil
        } catch CompanionClientError.unsupportedLiveSignalLayout(let version) {
            failure = "This controller sends live signals in layout \(version), which this app cannot read."
            return
        } catch {
            failure = "Live signals are not available."
            return
        }
        for await next in stream {
            receive(next, at: clock.now)
        }
    }

    func receive(_ next: LiveSignalFrame, at now: ContinuousClock.Instant) {
        frame = next
        // The stall frame is synthetic, not something the controller sent.
        if next != .unknown { arrivals.append(now) }
        arrivals.removeAll { now - $0 > .seconds(1) }
        framesPerSecond = arrivals.count
    }

    private func clear() {
        frame = .unknown
        arrivals.removeAll()
        framesPerSecond = 0
    }
}
