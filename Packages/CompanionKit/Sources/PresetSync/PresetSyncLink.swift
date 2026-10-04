import Foundation
import CompanionProtocol

/// What the preset sync flow needs from the connection layer.
///
/// The app's BLE adapter implements it; tests and previews use an in-memory
/// controller.
public protocol PresetSyncLink: Sendable {
    /// A client for the current connection to a paired controller, with
    /// device info already read. Throws when no controller is connected.
    func currentClient() async throws -> CompanionClient

    /// Waits until the controller has restarted after a commit or a revert
    /// and the link is back, then returns a client for the new connection
    /// with device info read. Throws when the controller does not come back
    /// in reasonable time.
    func clientAfterRestart() async throws -> CompanionClient
}
