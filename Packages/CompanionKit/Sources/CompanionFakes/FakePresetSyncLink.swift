import Foundation
import CompanionProtocol
import PresetSync

/// A `PresetSyncLink` over a `FakeController`. Waiting for the restart calls
/// `FakeController.restart()` after `restartDelay`.
public final class FakePresetSyncLink: PresetSyncLink, @unchecked Sendable {
    public let controller: FakeController
    public let restartDelay: Duration
    /// Returns from `clientAfterRestart()` without restarting the controller,
    /// as an adapter that answers too early would.
    public var skipsRestart = false
    private let lock = NSLock()
    private var restartCount = 0

    public init(controller: FakeController, restartDelay: Duration = .zero) {
        self.controller = controller
        self.restartDelay = restartDelay
    }

    /// How many times the flow waited for a restart.
    public var restarts: Int {
        lock.withLock { restartCount }
    }

    public func currentClient() async throws -> CompanionClient {
        let client = CompanionClient(transport: controller)
        try await client.readDeviceInfo()
        return client
    }

    public func clientAfterRestart() async throws -> CompanionClient {
        lock.withLock { restartCount += 1 }
        if restartDelay > .zero { try await Task.sleep(for: restartDelay) }
        if !skipsRestart { controller.restart() }
        return try await currentClient()
    }
}
