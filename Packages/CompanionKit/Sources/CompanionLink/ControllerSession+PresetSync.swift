import Foundation
import CompanionProtocol
import PresetSync

extension ControllerSession: PresetSyncLink {
    /// How long `clientAfterRestart()` waits for the controller to come back.
    public static let restartTimeout: Duration = .seconds(60)

    /// The session's client once everything is read. Throws while the link
    /// is down or still loading, so a sync never shares the client with the
    /// session's own reads.
    public func currentClient() async throws -> CompanionClient {
        guard phase == .ready else { throw CompanionClientError.transport(.notConnected) }
        return client
    }

    public func clientAfterRestart() async throws -> CompanionClient {
        try await clientAfterRestart(timeout: Self.restartTimeout)
    }

    /// Waits until the session is ready on a connection whose Config status
    /// is no longer `RestartPending`: the controller restarted, the link came
    /// back, and the session re-read device info and config.
    ///
    /// When the restart never happened (a command whose outcome was unknown
    /// and did not run), status is not `RestartPending` and this returns at
    /// once, so the caller checks what actually runs.
    func clientAfterRestart(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(100)
    ) async throws -> CompanionClient {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if phase == .ready,
               let status = try? await client.readConfigStatus(),
               status.state != .known(.restartPending),
               phase == .ready {
                return client
            }
            try await Task.sleep(for: pollInterval)
        }
        throw CompanionClientError.timedOut(.readConfigStatus)
    }
}
