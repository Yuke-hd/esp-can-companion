import Observation
import PresetSync
import CompanionProtocol

/// Owns the local draft independently of the configuration reported by the car.
@MainActor
@Observable
final class SetupSelection {
    enum Status: Equatable {
        case none, pending, onCar
    }

    private(set) var basePreset: Preset?
    private(set) var editableConfig: ControllerConfig?
    private var invalidFields: Set<String> = []
    private(set) var draftRevision = 0

    var rpmIssues: [RPMValidation.Issue] {
        editableConfig.map { RPMValidation.issues(in: $0) } ?? []
    }

    var hasInputErrors: Bool { !invalidFields.isEmpty || !rpmIssues.isEmpty }

    func rpmError(for action: SetupAction, field: RPMValidation.Issue.Field) -> String? {
        guard let index = editableConfig?.rules.firstIndex(where: { rule in
            guard rule.action == action.rawValue else { return false }
            switch rule {
            case .range(let range): return range.signalKey == "vehicle.engine_rpm" && action == .rpmFill
            case .sampledState(let condition, _):
                return condition.signalKey == "vehicle.engine_rpm" && action == .redZone
                    && (condition.comparison == .greater || condition.comparison == .greaterOrEqual)
            default: return false
            }
        }) else { return nil }
        return rpmIssues.first { $0.ruleIndex == index && $0.field == field }?.message
    }

    func setFieldValidity(_ field: String, isValid: Bool) {
        if isValid { invalidFields.remove(field); return }
        invalidFields.insert(field)
    }

    var preset: Preset? {
        guard var preset = basePreset, let editableConfig else { return nil }
        preset.config = editableConfig
        guard isModified else { return preset }
        preset.id += "-tweaked"
        preset.name += " (tweaked)"
        preset.summary = "A custom setup based on \(basePreset?.name ?? preset.name). Check its settings and actions before sending."
        return preset
    }

    var tweaks: ConfigTweaks? {
        editableConfig.map { ConfigTweaks(config: $0) }
    }

    var isModified: Bool {
        guard let basePreset, let editableConfig else { return false }
        return editableConfig != basePreset.config
    }

    var changeCount: Int {
        guard let original = basePreset?.config else { return 0 }
        return tweaks?.changeCount(from: original) ?? 0
    }

    func select(_ preset: Preset) {
        guard basePreset?.id != preset.id else { return }
        basePreset = preset
        editableConfig = preset.config
        invalidFields.removeAll()
        draftRevision += 1
    }

    func setRPMInputRange(_ range: RPMInputRange) {
        guard let updated = tweaks?.settingRPMInputRange(range) else { return }
        updateConfig(updated.config)
    }

    func setRedZoneThresholds(_ thresholds: RedZoneThresholds) {
        guard let updated = tweaks?.settingRedZoneThresholds(thresholds) else { return }
        updateConfig(updated.config)
    }

    func setOutput(_ settings: ActionOutputSettings, for action: SetupAction) {
        guard let updated = tweaks?.settingOutput(settings, for: action) else { return }
        updateConfig(updated.config)
    }

    /// Accepts a complete editor draft; local RPM checks also apply to advanced edits.
    func updateConfig(_ config: ControllerConfig) {
        guard basePreset != nil else { return }
        editableConfig = config
    }

    func resetTweaks() {
        editableConfig = basePreset?.config
        invalidFields.removeAll()
        draftRevision += 1
    }

    func status(activePresetID: String?) -> Status {
        guard let preset else { return .none }
        return preset.id == activePresetID ? .onCar : .pending
    }

    func status(active: PresetSyncModel.ActiveConfig?) -> Status {
        guard let active else { return preset == nil ? .none : .pending }
        return status(activeSource: active.source, activeCRC32: active.crc32)
    }

    func status(activeSource: ConfigSource, activeCRC32: UInt32) -> Status {
        guard let preset else { return .none }
        guard activeSource == .known(.persistedOverride),
              let document = try? preset.config.encodedJSON() else { return .pending }
        return CRC32.checksum(document) == activeCRC32 ? .onCar : .pending
    }

    func canSend(isConnected: Bool, phase: PresetSyncModel.Phase) -> Bool {
        isConnected && preset != nil && phase == .idle && !hasInputErrors
    }
}
