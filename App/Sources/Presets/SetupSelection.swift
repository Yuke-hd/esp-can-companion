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

    /// The id of a base built from the controller's own config.
    static let controllerPresetID = "controller"

    private(set) var basePreset: Preset?
    /// The user picked the base; until then Setup follows the controller.
    private(set) var hasUserChoice = false
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

    /// The base is the controller's own config rather than a bundled preset.
    var isControllerBase: Bool { basePreset?.id == Self.controllerPresetID }

    func select(_ preset: Preset) {
        hasUserChoice = true
        guard basePreset?.id != preset.id else { return }
        replaceBase(with: preset)
    }

    /// Starts the draft from what the controller runs: its bundled preset when
    /// it matches one, else the config itself. Ignored once the user has
    /// picked a base or changed the draft.
    func followController(_ active: PresetSyncModel.ActiveConfig, presets: [Preset]) {
        guard !hasUserChoice, !isModified, !hasInputErrors,
              let base = Self.base(for: active, presets: presets), base != basePreset else { return }
        replaceBase(with: base)
    }

    /// Before the controller is read, the first bundled preset stands in.
    func selectFallback(_ preset: Preset) {
        guard basePreset == nil else { return }
        replaceBase(with: preset)
    }

    /// The base the controller's config gives, or `nil` when it was not read.
    static func base(for active: PresetSyncModel.ActiveConfig, presets: [Preset]) -> Preset? {
        if let preset = presets.first(where: { $0.id == active.presetID }) { return preset }
        guard let config = active.config else { return nil }
        let factory = active.isFactory
        return Preset(id: controllerPresetID, name: factory ? "Factory" : "Custom",
                      summary: factory ? "The controller's factory config, as it runs on the car."
                                       : "The config saved on the controller, as it runs on the car.",
                      config: config)
    }

    private func replaceBase(with preset: Preset) {
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
        if let config = active.config, let preset { return preset.config == config ? .onCar : .pending }
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
