import Foundation
import Observation
import CompanionProtocol

/// The preset sync flow: push a bundled preset, show the controller's
/// verdict, and revert to factory.
///
/// The controller is the only validator. The model never reports success
/// until the controller has restarted and Config status shows the change
/// running; anything less ends in a `SyncFailure`.
@MainActor
@Observable
public final class PresetSyncModel {
    /// What a push or revert changes.
    public enum Target: Equatable, Sendable {
        case preset(Preset)
        case factory
    }

    public enum Phase: Equatable, Sendable {
        case idle
        /// Waiting for the user to confirm.
        case confirming(Target)
        /// Sending the document; `fraction` runs from 0 to 1.
        case uploading(Preset, fraction: Double)
        /// All bytes sent; the controller is validating and saving.
        case validating(Preset)
        /// Sending the revert command.
        case reverting
        /// Waiting for the controller to restart and checking what runs.
        case restarting(Target)
        case succeeded(Target)
        case failed(Target, SyncFailure)

        /// A push or revert is running and cannot be dismissed.
        public var isBusy: Bool {
            switch self {
            case .uploading, .validating, .reverting, .restarting: true
            default: false
            }
        }
    }

    /// The config the controller reported on the last read.
    public struct ActiveConfig: Equatable, Sendable {
        public var source: ConfigSource
        public var crc32: UInt32
        /// The bundled preset this config matches, if any.
        public var presetID: String?
        /// Why a saved config was ignored at the last start-up, if it was.
        public var bootDiagnostic: BootDiagnostic?
        public var lightingSetupFailed: Bool

        public var isFactory: Bool { source == .known(.factory) }
    }

    public let presets: [Preset]
    public private(set) var phase: Phase = .idle
    public private(set) var active: ActiveConfig?
    /// Why the last read of the active config failed.
    public private(set) var refreshError: String?
    /// Called after a push or revert is confirmed, so other screens can
    /// re-read the controller.
    public var onChange: (@MainActor () -> Void)?

    private let link: PresetSyncLink

    public init(presets: [Preset], link: PresetSyncLink) {
        self.presets = presets
        self.link = link
    }

    // MARK: User actions

    public func requestPush(_ preset: Preset) {
        guard !phase.isBusy else { return }
        phase = .confirming(.preset(preset))
    }

    public func requestRevert() {
        guard !phase.isBusy else { return }
        phase = .confirming(.factory)
    }

    /// Dismisses a confirmation or a result. Does nothing while busy.
    public func dismiss() {
        guard !phase.isBusy else { return }
        phase = .idle
    }

    /// Runs the confirmed push or revert to its verdict.
    public func confirm() async {
        guard case .confirming(let target) = phase else { return }
        switch target {
        case .preset(let preset): await push(preset)
        case .factory: await revert()
        }
    }

    /// Reads the active config from the controller.
    public func refresh() async {
        do {
            try await refresh(using: link.currentClient())
        } catch {
            active = nil
            refreshError = SyncFailure.describe(error)
        }
    }

    // MARK: Flows

    private func push(_ preset: Preset) async {
        let target = Target.preset(preset)
        phase = .uploading(preset, fraction: 0)
        let receipt: ConfigUploadReceipt
        do {
            let client = try await link.currentClient()
            receipt = try await client.uploadConfig(preset.config) { progress in
                Task { @MainActor [weak self] in self?.report(progress, for: preset) }
            }
        } catch CompanionClientError.commitOutcomeUnknown {
            await settleUnknownOutcome(target)
            return
        } catch {
            phase = .failed(target, .push(error))
            return
        }

        phase = .restarting(target)
        do {
            let client = try await link.clientAfterRestart()
            let status = try await client.readConfigStatus()
            try? await refresh(using: client)
            guard let crc = receipt.savedCRC32 else {
                // Saved, but the Saved notification with its CRC never arrived.
                phase = .failed(target, .outcomeUnknown(push: true))
                return
            }
            if status.isActive(savedCRC32: crc) {
                phase = .succeeded(target)
                onChange?()
            } else {
                phase = .failed(target, .notActive(status))
            }
        } catch {
            phase = .failed(target, .outcomeUnknown(push: true))
        }
    }

    private func revert() async {
        phase = .reverting
        do {
            let client = try await link.currentClient()
            try await client.send(.revertToFactory)
        } catch CompanionClientError.commandOutcomeUnknown {
            // The controller may have reverted; reconnect and check below.
        } catch {
            phase = .failed(.factory, .revert(error))
            return
        }

        phase = .restarting(.factory)
        do {
            let client = try await link.clientAfterRestart()
            let status = try await client.readConfigStatus()
            try? await refresh(using: client)
            if status.activeSource == .known(.factory) {
                phase = .succeeded(.factory)
                onChange?()
            } else {
                phase = .failed(.factory, .revertNotConfirmed(status))
            }
        } catch {
            phase = .failed(.factory, .outcomeUnknown(push: false))
        }
    }

    /// The link dropped during commit. Reconnect to show what runs now, but
    /// without the saved CRC the push cannot be confirmed.
    private func settleUnknownOutcome(_ target: Target) async {
        phase = .restarting(target)
        if let client = try? await link.clientAfterRestart() {
            try? await refresh(using: client)
        }
        phase = .failed(target, .outcomeUnknown(push: true))
    }

    private func report(_ progress: ConfigUploadProgress, for preset: Preset) {
        guard case .uploading(let current, let fraction) = phase, current == preset,
              progress.fraction >= fraction
        else { return }
        phase = progress.fraction >= 1 ? .validating(preset) : .uploading(preset, fraction: progress.fraction)
    }

    private func refresh(using client: CompanionClient) async throws {
        let status = try await client.readConfigStatus()
        var presetID: String?
        if status.activeSource == .known(.persistedOverride),
           let config = try? await client.readActiveConfig().decodeConfig() {
            presetID = presets.first { $0.config == config }?.id
        }
        active = ActiveConfig(
            source: status.activeSource,
            crc32: status.activeCRC32,
            presetID: presetID,
            bootDiagnostic: status.bootDiagnostic,
            lightingSetupFailed: status.bootFlags.contains(.lightingSetupFailed)
        )
        refreshError = nil
    }
}
