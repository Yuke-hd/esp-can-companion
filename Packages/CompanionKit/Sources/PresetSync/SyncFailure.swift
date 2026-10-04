import Foundation
import CompanionProtocol

/// Why a push or a revert did not end with a confirmed result, ready to show.
public struct SyncFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The controller's validation rejected the document. Nothing changed.
        case rejected
        /// The controller restarted, but the preset is not the running config.
        case notActive
        /// The phone cannot tell whether the change took effect.
        case outcomeUnknown
        /// The controller could not update its storage.
        case storage
        /// Anything else: no link, a timeout before commit, an incompatible
        /// controller.
        case failed
    }

    public var kind: Kind
    public var title: String
    public var message: String
    /// The controller's error code, such as `semantic · invalidValue · zoneOutOfRange`.
    public var code: String?
    /// The field the controller blamed, such as `outputs[4].zone.length`.
    public var field: String?

    public init(kind: Kind, title: String, message: String, code: String? = nil, field: String? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.code = code
        self.field = field
    }
}

extension SyncFailure {
    /// The verdict for a failed push.
    static func push(_ error: Error) -> SyncFailure {
        guard let error = error as? CompanionClientError else {
            return SyncFailure(kind: .failed, title: "Push failed", message: describe(error))
        }
        switch error {
        case .configRejected(let rejection):
            return SyncFailure(
                kind: .rejected,
                title: "The controller rejected this preset",
                message: "Its validation found a problem, so it kept the current config.",
                code: code(rejection),
                field: field(rejection)
            )
        case .applyRejected(let rejection):
            return SyncFailure(
                kind: .rejected,
                title: "The controller rejected this preset",
                message: "A trial run of the config failed, so it kept the current config.",
                code: code(rejection),
                field: field(rejection)
            )
        case .storageFailed:
            return SyncFailure(
                kind: .storage,
                title: "The controller could not save the preset",
                message: "Which config it loads at its next start is uncertain. Push again, or revert to factory now."
            )
        case .commitOutcomeUnknown:
            return outcomeUnknown(push: true)
        case .checksumMismatch:
            return SyncFailure(
                kind: .failed,
                title: "The upload was corrupted",
                message: "The controller discarded it and kept the current config. Push again."
            )
        default:
            return SyncFailure(kind: .failed, title: "Push failed", message: describe(error))
        }
    }

    /// The verdict for a failed revert.
    static func revert(_ error: Error) -> SyncFailure {
        if case CompanionClientError.controllerError(.known(.storageFailure), _) = error {
            return SyncFailure(
                kind: .storage,
                title: "The controller could not revert",
                message: "It kept its current config, but which config it loads at its next start is uncertain. Try again."
            )
        }
        return SyncFailure(kind: .failed, title: "Revert failed", message: describe(error))
    }

    static func outcomeUnknown(push: Bool) -> SyncFailure {
        SyncFailure(
            kind: .outcomeUnknown,
            title: "Could not confirm the result",
            message: push
                ? "The link dropped before the controller confirmed the save. Push again; sending the same preset twice is harmless."
                : "The link dropped before the controller confirmed the revert. Check the active config, and revert again if needed."
        )
    }

    /// The controller restarted but is not running the uploaded preset.
    static func notActive(_ status: ConfigStatus) -> SyncFailure {
        if let diagnostic = status.bootDiagnostic {
            return SyncFailure(
                kind: .notActive,
                title: "The controller could not load the preset",
                message: "It fell back to the factory config at start-up.",
                code: join([diagnostic.code.description, diagnostic.validation.description], skipping: ["none"])
            )
        }
        if status.bootFlags.contains(.lightingSetupFailed) {
            return SyncFailure(
                kind: .notActive,
                title: "Lighting failed to start",
                message: "The controller saved the preset, but its lights failed to start with it. Revert to factory or push another preset."
            )
        }
        return SyncFailure(
            kind: .notActive,
            title: "The preset is not running",
            message: "The controller restarted with a different config. Push again."
        )
    }

    /// The factory config is selected, but lighting setup failed at boot:
    /// the LEDs are off and CAN acquisition did not start.
    static let factoryLightingFailed = SyncFailure(
        kind: .notActive,
        title: "Lighting failed to start",
        message: "The controller restarted with its factory config, but its lights failed to start. "
            + "The controller may need a firmware update."
    )

    /// A storage failure right after another one.
    static let storageFailing = SyncFailure(
        kind: .storage,
        title: "The controller's storage is failing",
        message: "It could not update its storage twice in a row. Which config it loads at its next start is uncertain, "
            + "and retrying is unlikely to help. The controller may need service."
    )

    static func revertNotConfirmed(_ status: ConfigStatus) -> SyncFailure {
        SyncFailure(
            kind: .notActive,
            title: "The factory config is not running",
            message: "The controller still reports a saved config as active. Revert again.",
            code: "active source: \(status.activeSource)"
        )
    }

    // MARK: Formatting

    static func code(_ rejection: ConfigRejection) -> String {
        join(
            [rejection.category.description, rejection.code.description, rejection.validation.description],
            skipping: ["none"]
        ) ?? "unknown"
    }

    static func field(_ rejection: ConfigRejection) -> String {
        let path = rejection.path.isEmpty || rejection.path == "$" ? "the whole document" : rejection.path
        return rejection.isPathTruncated ? path + "…" : path
    }

    static func code(_ rejection: ApplyRejection) -> String {
        join(
            [
                "stage \(rejection.stage)",
                rejection.validation.description,
                rejection.binding.description,
                rejection.engine.description,
            ],
            skipping: ["none", "ok"]
        ) ?? "unknown"
    }

    static func field(_ rejection: ApplyRejection) -> String {
        rejection.section == .known(.document) ? "the whole document" : "\(rejection.section)[\(rejection.index)]"
    }

    static func join(_ parts: [String], skipping: Set<String>) -> String? {
        let kept = parts.filter { !skipping.contains($0) }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? CompanionClientError else { return String(describing: error) }
        switch error {
        case .deviceInfoNotRead, .transport(.notConnected):
            return "No controller is connected."
        case .unsupportedProtocol:
            return "This controller needs a newer app, or its firmware needs an update."
        case .configSchemaMismatch(let document, let controller):
            return "The preset uses config version \(document), but the controller expects version \(controller)."
        case .unreadableDocumentVersion:
            return "The preset has no readable config version, so it was not sent."
        case .documentTooLarge(let size, let maximum):
            return "The preset is \(size) bytes; the controller accepts at most \(maximum)."
        case .mtuTooSmall:
            return "The Bluetooth link cannot carry a config transfer. Reconnect and try again."
        case .uploadInProgress:
            return "Another upload is running."
        case .timedOut:
            return "The controller did not answer in time. Nothing was changed."
        case .transport(.disconnected):
            return "The link dropped. Nothing was changed."
        default:
            return "\(error)"
        }
    }
}
