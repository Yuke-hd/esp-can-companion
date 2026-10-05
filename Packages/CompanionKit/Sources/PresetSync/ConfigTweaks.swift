import Foundation
import CompanionProtocol

/// The named outputs exposed by the compact Setup controls.
public enum SetupAction: String, CaseIterable, Sendable {
    case rpmFill = "rpm_fill", redZone = "red_zone", brake
}

public struct RPMInputRange: Equatable, Sendable {
    public let lower: Double
    public let upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }
}

public struct RedZoneThresholds: Equatable, Sendable {
    public let triggerAbove: Double
    public let releaseBelow: Double?

    public init(triggerAbove: Double, releaseBelow: Double?) {
        self.triggerAbove = triggerAbove
        self.releaseBelow = releaseBelow
    }
}

public struct ActionOutputSettings: Equatable, Sendable {
    public let color: ControllerConfig.Color
    public let zone: ControllerConfig.Zone
    public let priority: Int

    public init(color: ControllerConfig.Color, zone: ControllerConfig.Zone, priority: Int) {
        self.color = color
        self.zone = zone
        self.priority = priority
    }
}

/// Edits existing settings without replacing unrelated rules or output bindings.
/// The controller remains responsible for validating the complete document.
public struct ConfigTweaks: Equatable, Sendable {
    public let config: ControllerConfig

    public init(config: ControllerConfig) {
        self.config = config
    }

    public var rpmInputRange: RPMInputRange? {
        guard let index = rpmRuleIndex, case .range(let rule) = config.rules[index] else { return nil }
        return RPMInputRange(lower: rule.input.from, upper: rule.input.to)
    }

    public var redZoneThresholds: RedZoneThresholds? {
        guard let index = redZoneRuleIndex,
              case .sampledState(let condition, let release) = config.rules[index],
              case .number(let trigger) = condition.operand else { return nil }
        return RedZoneThresholds(triggerAbove: trigger, releaseBelow: release)
    }

    public func output(for action: SetupAction) -> ActionOutputSettings? {
        guard let binding = config.outputs.first(where: { $0.action == action.rawValue }),
              let zone = Self.zoneBinding(binding) else { return nil }
        return ActionOutputSettings(color: zone.color, zone: zone.zone, priority: zone.priority)
    }

    public func settingRPMInputRange(_ range: RPMInputRange) -> ConfigTweaks {
        guard let index = rpmRuleIndex, case .range(var rule) = config.rules[index] else { return self }
        rule.input = .init(from: range.lower, to: range.upper)
        var updated = config
        updated.rules[index] = .range(rule)
        return ConfigTweaks(config: updated)
    }

    public func settingRedZoneThresholds(_ thresholds: RedZoneThresholds) -> ConfigTweaks {
        guard let index = redZoneRuleIndex,
              case .sampledState(var condition, _) = config.rules[index] else { return self }
        condition.operand = .number(thresholds.triggerAbove)
        var updated = config
        updated.rules[index] = .sampledState(condition, releaseThreshold: thresholds.releaseBelow)
        return ConfigTweaks(config: updated)
    }

    public func settingOutput(_ settings: ActionOutputSettings, for action: SetupAction) -> ConfigTweaks {
        guard let index = config.outputs.firstIndex(where: { $0.action == action.rawValue }),
              var binding = Self.zoneBinding(config.outputs[index]) else { return self }
        binding.color = settings.color
        binding.zone = settings.zone
        binding.priority = settings.priority
        var updated = config
        updated.outputs[index] = Self.replacingZone(in: config.outputs[index], with: binding)
        return ConfigTweaks(config: updated)
    }

    /// Number of edited, added or removed config entries, including full editor changes.
    public func changeCount(from original: ControllerConfig) -> Int {
        Self.differences(config.actions, original.actions)
            + Self.differences(config.rules, original.rules)
            + Self.differences(config.outputs, original.outputs)
            + (config.version == original.version ? 0 : 1)
    }

    private var rpmRuleIndex: Int? {
        config.rules.firstIndex {
            guard case .range(let rule) = $0 else { return false }
            return rule.action == SetupAction.rpmFill.rawValue && rule.signalKey == "vehicle.engine_rpm"
        }
    }

    private var redZoneRuleIndex: Int? {
        config.rules.firstIndex {
            guard case .sampledState(let condition, _) = $0,
                  case .number = condition.operand else { return false }
            return condition.action == SetupAction.redZone.rawValue
                && condition.signalKey == "vehicle.engine_rpm"
                && (condition.comparison == .greater || condition.comparison == .greaterOrEqual)
        }
    }

    private static func zoneBinding(_ output: ControllerConfig.OutputBinding) -> ControllerConfig.ZoneBinding? {
        switch output {
        case .ledFill(let binding), .ledSolid(let binding), .ledTransient(let binding, _): binding
        case .ledEffect: nil
        }
    }

    private static func replacingZone(in output: ControllerConfig.OutputBinding, with binding: ControllerConfig.ZoneBinding) -> ControllerConfig.OutputBinding {
        switch output {
        case .ledFill: .ledFill(binding)
        case .ledSolid: .ledSolid(binding)
        case .ledTransient(_, let duration): .ledTransient(binding, durationMs: duration)
        case .ledEffect: output
        }
    }

    private static func differences<Element: Equatable>(_ current: [Element], _ original: [Element]) -> Int {
        let changes = current.difference(from: original)
        let insertions = changes.filter {
            if case .insert = $0 { return true }
            return false
        }.count
        return max(insertions, changes.count - insertions)
    }
}
