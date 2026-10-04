import Foundation

/// The Config status characteristic.
public struct ConfigStatus: Equatable, Sendable {
    public enum StateCode: UInt8, Equatable, Sendable {
        case idle = 0
        case receiving = 1
        case restartPending = 2
    }

    public enum ResultCode: UInt8, Equatable, Sendable {
        case none = 0
        case saved = 1
        case configRejected = 2
        case applyRejected = 3
        case storageFailed = 4
        case aborted = 5
        case timedOut = 6
        case checksumMismatch = 7
        case interrupted = 8
    }

    public struct BootFlags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        /// A persisted override was invalid; the factory config is active.
        /// `bootDiagnostic` gives the reason.
        public static let overrideInvalid = BootFlags(rawValue: 1 << 0)
        /// Reading the persisted override failed; the factory config is active.
        public static let overrideReadFailed = BootFlags(rawValue: 1 << 1)
        /// No config store this boot, so uploads fail with `StorageFailure`.
        public static let noConfigStore = BootFlags(rawValue: 1 << 2)
        /// Lighting setup failed: LEDs are off and CAN acquisition did not start.
        public static let lightingSetupFailed = BootFlags(rawValue: 1 << 3)
    }

    public var state: WireValue<StateCode>
    public var result: WireValue<ResultCode>
    public var bootFlags: BootFlags
    public var activeSource: ConfigSource
    public var activeLength: UInt16
    public var activeCRC32: UInt32
    /// Start `total_length` while receiving.
    public var transferLength: UInt16
    /// Bytes accepted so far while receiving; the offset to resume from.
    public var receivedLength: UInt16
    /// Canonical length for `saved`.
    public var savedLength: UInt16
    /// Canonical CRC for `saved`. After the restart, `activeCRC32` equals it
    /// when the upload is active.
    public var savedCRC32: UInt32
    /// Set for `configRejected`.
    public var rejection: ConfigRejection?
    /// Set for `applyRejected`.
    public var applyRejection: ApplyRejection?
    /// Why the persisted override was ignored at boot (boot flag 0).
    public var bootDiagnostic: BootDiagnostic?

    public static let minimumLength = 35
    public static let maximumPathLength = 26

    public init(decoding value: Data) throws {
        var reader = ByteReader(value)
        state = WireValue(rawValue: try reader.u8("state"))
        result = WireValue(rawValue: try reader.u8("result"))
        bootFlags = BootFlags(rawValue: try reader.u8("boot_flags"))
        activeSource = ConfigSource(rawValue: try reader.u8("active_source"))
        activeLength = try reader.u16("active_length")
        activeCRC32 = try reader.u32("active_crc32")
        transferLength = try reader.u16("transfer_length")
        receivedLength = try reader.u16("received_length")
        savedLength = try reader.u16("saved_length")
        savedCRC32 = try reader.u32("saved_crc32")
        let category = WireValue<ConfigErrorCategory>(rawValue: try reader.u8("diag_category"))
        let code = WireValue<ConfigErrorCode>(rawValue: try reader.u8("diag_code"))
        let validation = WireValue<ValidationError>(rawValue: try reader.u8("diag_validation"))
        let index = try reader.u16("diag_index")
        let applyStage = WireValue<ApplyStage>(rawValue: try reader.u8("apply_stage"))
        let applyValidation = WireValue<ValidationError>(rawValue: try reader.u8("apply_validation"))
        let applySection = WireValue<ConfigSection>(rawValue: try reader.u8("apply_section"))
        let applyIndex = try reader.u16("apply_index")
        let applyBinding = WireValue<BindingStatus>(rawValue: try reader.u8("apply_binding"))
        let applyEngine = WireValue<EngineConfigStatus>(rawValue: try reader.u8("apply_engine"))
        let bootCode = WireValue<ConfigErrorCode>(rawValue: try reader.u8("boot_diag_code"))
        let bootValidation = WireValue<ValidationError>(rawValue: try reader.u8("boot_diag_validation"))
        let pathInfo = try reader.u8("path_info")
        let pathLength = Int(pathInfo & 0x7F)
        guard pathLength <= Self.maximumPathLength else {
            throw ProtocolDecodingError.invalidValue(field: "path_info")
        }
        let pathBytes = try reader.bytes(pathLength, "path")
        guard let path = String(data: pathBytes, encoding: .utf8) else {
            throw ProtocolDecodingError.invalidValue(field: "path")
        }

        rejection = result == .known(.configRejected)
            ? ConfigRejection(
                category: category,
                code: code,
                validation: validation,
                index: index,
                path: path,
                isPathTruncated: pathInfo & 0x80 != 0
            )
            : nil
        applyRejection = result == .known(.applyRejected)
            ? ApplyRejection(
                stage: applyStage,
                validation: applyValidation,
                section: applySection,
                index: applyIndex,
                binding: applyBinding,
                engine: applyEngine
            )
            : nil
        bootDiagnostic = bootFlags.contains(.overrideInvalid)
            ? BootDiagnostic(code: bootCode, validation: bootValidation)
            : nil
    }

    /// True after a restart when the uploaded config with `savedCRC32` is the
    /// one running: a persisted override with that CRC, with no boot fallback
    /// or lighting failure.
    public func isActive(savedCRC32 crc: UInt32) -> Bool {
        activeSource == .known(.persistedOverride)
            && activeCRC32 == crc
            && bootFlags.isDisjoint(with: [.overrideInvalid, .lightingSetupFailed])
    }
}

/// Why the controller's loader rejected an uploaded document.
public struct ConfigRejection: Error, Equatable, Sendable {
    public var category: WireValue<ConfigErrorCategory>
    public var code: WireValue<ConfigErrorCode>
    public var validation: WireValue<ValidationError>
    /// Position of the failing entry in its section; saturates at `0xFFFF`.
    public var index: UInt16
    /// The persisted field path, such as `outputs[3].zone.length` or `$`.
    public var path: String
    /// The controller cut a longer path at a UTF-8 character boundary.
    public var isPathTruncated: Bool

    public init(
        category: WireValue<ConfigErrorCategory>,
        code: WireValue<ConfigErrorCode>,
        validation: WireValue<ValidationError>,
        index: UInt16,
        path: String,
        isPathTruncated: Bool
    ) {
        self.category = category
        self.code = code
        self.validation = validation
        self.index = index
        self.path = path
        self.isPathTruncated = isPathTruncated
    }
}

/// Why the dry-run apply rejected an uploaded document.
public struct ApplyRejection: Error, Equatable, Sendable {
    public var stage: WireValue<ApplyStage>
    public var validation: WireValue<ValidationError>
    public var section: WireValue<ConfigSection>
    /// The entry's position in `section`; saturates at `0xFFFF`.
    public var index: UInt16
    public var binding: WireValue<BindingStatus>
    public var engine: WireValue<EngineConfigStatus>

    public init(
        stage: WireValue<ApplyStage>,
        validation: WireValue<ValidationError>,
        section: WireValue<ConfigSection>,
        index: UInt16,
        binding: WireValue<BindingStatus>,
        engine: WireValue<EngineConfigStatus>
    ) {
        self.stage = stage
        self.validation = validation
        self.section = section
        self.index = index
        self.binding = binding
        self.engine = engine
    }
}

/// Why a persisted override was ignored at boot.
public struct BootDiagnostic: Equatable, Sendable {
    public var code: WireValue<ConfigErrorCode>
    public var validation: WireValue<ValidationError>
}

// MARK: - Wire codes (config-transfer.md, "Wire codes")

public enum ConfigErrorCategory: UInt8, Equatable, Sendable {
    case none = 0, parse, structural, semantic
}

public enum ConfigErrorCode: UInt8, Equatable, Sendable {
    case none = 0
    case malformedJSON, embeddedNul, inputTooLarge, nestingLimitExceeded, rootTypeMismatch
    case missingField, unknownField, typeMismatch, invalidValue, schemaValidation, resourceExhausted
}

public enum ValidationError: UInt8, Equatable, Sendable {
    case none = 0
    case unsupportedVersion, emptyActionName, duplicateActionName, undeclaredAction, duplicateAction
    case emptySignalKey, unknownComparison, unknownFreshness, unknownEventEdge, emptyChoice
    case invalidOperand, unsupportedComparison, invalidHysteresis, invalidRange, unknownLedEffect
    case unknownFillDirection, emptyZone, zoneOutOfRange, invalidColor, invalidPriority
    case duplicateBinding, invalidDuration, incompatibleActionKind
}

public enum ConfigSection: UInt8, Equatable, Sendable {
    case document = 0, actions, rules, outputs
}

public enum ApplyStage: UInt8, Equatable, Sendable {
    case complete = 0, validation, actionID, outputBinding, sinkRegistration, rule
}

/// `local_argb_actions::BindingStatus`.
public enum BindingStatus: UInt8, Equatable, Sendable {
    case ok = 0, invalidAction, duplicateBinding, capacityExceeded, invalidEffect
}

/// `action_engine::ConfigStatus`.
public enum EngineConfigStatus: UInt8, Equatable, Sendable {
    case ok = 0
    case invalidState, capacityExceeded, duplicateSink, invalidAction, duplicateAction, unknownSignal
    case unsupportedCapability, typeMismatch, unknownChoice, invalidOperand, unsupportedComparison
    case invalidRange, invalidHysteresis
}
