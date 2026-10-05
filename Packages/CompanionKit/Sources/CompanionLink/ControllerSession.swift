import Foundation
import Observation
import BLETransport
import CompanionProtocol
import PresetSync

/// The controller as the app sees it: the link from `ConnectionManager`, plus
/// device info, config status and the active config read with the protocol
/// client each time the link comes up.
///
/// On every link change the client's cached device info is cleared, and on
/// every new connection it is read again before anything else, so nothing
/// read from a previous connection (or a controller that restarted with new
/// firmware) is reused.
@MainActor
@Observable
public final class ControllerSession {
    public enum Phase: Equatable, Sendable {
        /// No paired link.
        case offline
        /// Linked; reading device info and config.
        case loading
        /// Everything was read.
        case ready
        /// Device info reports a protocol major this app does not speak.
        case incompatible(major: UInt8)
        /// A read failed. `reload()` tries again.
        case failed(String)
    }

    /// The active config as read back from the controller.
    public enum ActiveConfig: Equatable, Sendable {
        /// The controller selected no config this boot.
        case none
        case summary(ConfigSummary)
        /// Read back, but this app cannot interpret it, for example a newer
        /// config schema version.
        case unreadable(String)
    }

    public let connection: ConnectionManager
    /// The protocol client for the connected controller. Its device info is
    /// already read whenever `phase` is `.ready`.
    @ObservationIgnored public let client: CompanionClient

    public private(set) var phase: Phase = .offline
    public private(set) var deviceInfo: DeviceInfo?
    public private(set) var configStatus: ConfigStatus?
    public private(set) var activeConfig: ActiveConfig?

    /// Bumped on every link change so results of an older load are dropped.
    @ObservationIgnored private var generation = 0
    /// The last reset or load. Each new one waits for it, so a reset from a
    /// disconnect can never land after the next connection's device info read.
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var stateObservation: ObservationToken?

    public init(connection: ConnectionManager, timeouts: CompanionClient.Timeouts = .init()) {
        self.connection = connection
        client = CompanionClient(transport: ConnectionManagerTransport(manager: connection), timeouts: timeouts)
        stateObservation = connection.observeState { [weak self] state in
            self?.linkChanged(state)
        }
        linkChanged(connection.state)
    }

    /// Reads everything again, for example after a failed read.
    public func reload() {
        linkChanged(connection.state)
    }

    // MARK: Loading

    private func linkChanged(_ state: LinkState) {
        generation += 1
        let current = generation
        deviceInfo = nil
        configStatus = nil
        activeConfig = nil
        phase = state.isConnected ? .loading : .offline

        let previous = work
        previous?.cancel()
        work = Task { [weak self, client = self.client] in
            await previous?.value
            await client.reset()
            guard state.isConnected, let self, !Task.isCancelled else { return }
            await self.load(generation: current)
        }
    }

    private func load(generation current: Int) async {
        do {
            let info = try await client.readDeviceInfo()
            guard generation == current else { return }
            deviceInfo = info
            let compatibility = info.compatibility()
            guard compatibility.isProtocolSupported else {
                phase = .incompatible(major: info.protocolMajor)
                return
            }

            let status = try await client.readConfigStatus()
            guard generation == current else { return }
            configStatus = status

            let active: ActiveConfig
            if status.activeSource == .known(.none) {
                active = .none
            } else {
                let readBack = try await client.readActiveConfig()
                guard generation == current else { return }
                active = Self.interpret(readBack, compatibility: compatibility, schema: info.configSchemaVersion)
            }
            activeConfig = active
            phase = .ready
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            phase = .failed(Self.describe(error))
        }
    }

    static func interpret(_ readBack: ConfigReadBack, compatibility: Compatibility, schema: UInt16) -> ActiveConfig {
        guard readBack.source != .known(.none), !readBack.document.isEmpty else { return .none }
        guard compatibility.canEditConfig else {
            return .unreadable("The controller uses config schema \(schema), which this app version cannot show.")
        }
        guard let config = try? readBack.decodeConfig() else {
            return .unreadable("The active config could not be read.")
        }
        let profile = ConfigSummary.profile(of: config, factory: knownConfigs.factory, presets: knownConfigs.presets)
        return .summary(ConfigSummary(config, profile: profile))
    }

    /// The factory profile and bundled presets, to name the active config.
    private static let knownConfigs = (factory: try? PresetCatalog.factory(), presets: (try? PresetCatalog.bundled()) ?? [])

    static func describe(_ error: Error) -> String {
        switch error as? CompanionClientError {
        case .timedOut?:
            "The controller did not answer in time."
        case .transport(.notConnected)?, .transport(.disconnected)?:
            "The link dropped while reading the controller."
        case .malformed?, .readBackInconsistent?:
            "The controller sent data this app could not read."
        case .controllerError(let code, _)?:
            "The controller refused the request (error \(code.rawValue))."
        default:
            "Could not read the controller."
        }
    }
}
