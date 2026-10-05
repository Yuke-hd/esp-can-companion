import Foundation
import CompanionProtocol
import PresetSync

/// A controller config in plain language: each action with what triggers it
/// and what it drives.
public struct ConfigSummary: Equatable, Sendable {
    public struct Action: Equatable, Sendable, Identifiable {
        /// The action's persisted name, such as `left_turn`.
        public var name: String
        /// The name for people, such as "Left turn".
        public var title: String
        /// One line per rule, such as "When turn state is left".
        public var triggers: [String]
        /// One line per output binding, such as "Lights LEDs 35–64".
        public var outputs: [String]

        public var id: String { name }
    }

    /// Which known config this is, as the Pit Wall profile names it.
    public enum Profile: Equatable, Sendable {
        case factory
        /// A bundled preset, by its display name.
        case preset(String)
        case custom
    }

    /// One output of the config, for the Pit Wall output stack.
    public struct Output: Equatable, Sendable, Identifiable {
        public enum Kind: String, Equatable, Sendable {
            case effect, fill, flash, solid
        }

        /// The action's persisted name.
        public var action: String
        public var title: String
        public var priority: Int
        public var kind: Kind
        /// The binding's LED color, nil for a built-in effect.
        public var color: ControllerConfig.Color?

        public var id: String { "\(action)-\(kind.rawValue)-\(priority)" }

        public init(action: String, title: String, priority: Int, kind: Kind, color: ControllerConfig.Color?) {
            self.action = action
            self.title = title
            self.priority = priority
            self.kind = kind
            self.color = color
        }
    }

    /// The engine RPM thresholds the config lights up at, for the shift
    /// lights and the RPM bar.
    public struct RPMBand: Equatable, Sendable {
        /// The input span of the first range rule on engine RPM.
        public var fill: ControllerConfig.Span?
        /// The lowest threshold of an "engine RPM above" rule.
        public var redline: Double?
    }

    public var actions: [Action]
    public var profile: Profile
    /// Outputs ordered by priority, highest first; one entry per action and
    /// kind, so hazard's two turn effects show once.
    public var outputStack: [Output]
    public var rpmBand: RPMBand

    public init(_ config: ControllerConfig, profile: Profile = .custom) {
        self.profile = profile
        outputStack = Self.outputStack(config)
        rpmBand = Self.rpmBand(config)
        actions = config.actions.map { action in
            Action(
                name: action.name,
                title: Self.humanize(action.name),
                triggers: config.rules.filter { $0.action == action.name }.map(Self.describe),
                outputs: config.outputs.filter { $0.action == action.name }.map(Self.describe)
            )
        }
    }

    /// The profile for `config` read back from `source`. The controller's
    /// source decides factory; only a persisted override is matched against
    /// the bundled presets, as Presets does.
    public static func profile(of config: ControllerConfig, source: ConfigSource, presets: [Preset]) -> Profile {
        switch source {
        case .known(.factory):
            return .factory
        case .known(.persistedOverride):
            if let preset = presets.first(where: { $0.config == config }) { return .preset(preset.name) }
            return .custom
        default:
            return .custom
        }
    }

    // MARK: Pit Wall

    static func outputStack(_ config: ControllerConfig) -> [Output] {
        var seen = Set<String>()
        var outputs: [Output] = []
        for binding in config.outputs {
            let output: Output
            switch binding {
            case .ledEffect(let effect):
                output = Output(action: effect.action, title: humanize(effect.action), priority: effect.priority, kind: .effect, color: nil)
            case .ledFill(let zone):
                output = Output(action: zone.action, title: humanize(zone.action), priority: zone.priority, kind: .fill, color: zone.color)
            case .ledTransient(let zone, _):
                output = Output(action: zone.action, title: humanize(zone.action), priority: zone.priority, kind: .flash, color: zone.color)
            case .ledSolid(let zone):
                output = Output(action: zone.action, title: humanize(zone.action), priority: zone.priority, kind: .solid, color: zone.color)
            }
            if seen.insert(output.id).inserted { outputs.append(output) }
        }
        // Stable: equal priorities keep the config's order.
        return outputs.enumerated()
            .sorted { $0.element.priority != $1.element.priority ? $0.element.priority > $1.element.priority : $0.offset < $1.offset }
            .map(\.element)
    }

    static func rpmBand(_ config: ControllerConfig) -> RPMBand {
        let rpm = "vehicle.engine_rpm"
        var fill: ControllerConfig.Span?
        var redline: Double?
        for rule in config.rules {
            switch rule {
            case .range(let range) where range.signalKey == rpm:
                fill = fill ?? range.input
            case .state(let condition), .sampledState(let condition, _), .event(let condition, _):
                guard condition.signalKey == rpm,
                      condition.comparison == .greater || condition.comparison == .greaterOrEqual,
                      case .number(let threshold) = condition.operand else { continue }
                redline = min(redline ?? threshold, threshold)
            default:
                continue
            }
        }
        return RPMBand(fill: fill, redline: redline)
    }

    // MARK: Rules

    static func describe(_ rule: ControllerConfig.Rule) -> String {
        switch rule {
        case .state(let condition):
            return "When \(describe(condition))"
        case .sampledState(let condition, let release):
            let base = "When \(describe(condition)), checked periodically"
            guard let release else { return base }
            return "\(base), releases at \(format(release))"
        case .event(let condition, let edge):
            switch edge {
            case .becomesTrue: return "Each time \(describe(condition)) starts"
            case .becomesFalse: return "Each time \(describe(condition)) ends"
            }
        case .range(let rule):
            return "Follows \(signalName(rule.signalKey)) from \(format(rule.input.from)) to \(format(rule.input.to))"
        }
    }

    static func describe(_ condition: ControllerConfig.Condition) -> String {
        let signal = signalName(condition.signalKey)
        switch (condition.comparison, condition.operand) {
        case (.equal, .boolean(let value)), (.notEqual, .boolean(let value)):
            let isTrue = (condition.comparison == .equal) == value
            return isTrue ? "\(signal) is on" : "\(signal) is off"
        default:
            return "\(signal) \(phrase(condition.comparison)) \(describe(condition.operand))"
        }
    }

    static func phrase(_ comparison: ControllerConfig.Comparison) -> String {
        switch comparison {
        case .equal: "is"
        case .notEqual: "is not"
        case .less: "is below"
        case .lessOrEqual: "is at most"
        case .greater: "is above"
        case .greaterOrEqual: "is at least"
        }
    }

    static func describe(_ operand: ControllerConfig.Operand) -> String {
        switch operand {
        case .boolean(let value): value ? "on" : "off"
        case .number(let value): format(value)
        case .choice(let choice): humanize(choice).lowercased()
        }
    }

    // MARK: Outputs

    static func describe(_ output: ControllerConfig.OutputBinding) -> String {
        switch output {
        case .ledEffect(let binding):
            return "\(humanize(binding.effect.rawValue)) LED effect"
        case .ledFill(let binding):
            return "Fills \(leds(binding.zone)) \(direction(binding.zone.direction))"
        case .ledTransient(let binding, let durationMs):
            return "Flashes \(leds(binding.zone)) for \(durationMs) ms"
        case .ledSolid(let binding):
            return "Lights \(leds(binding.zone))"
        }
    }

    static func leds(_ zone: ControllerConfig.Zone) -> String {
        guard zone.length > 1 else { return "LED \(zone.start)" }
        return "LEDs \(zone.start)–\(zone.start + zone.length - 1)"
    }

    static func direction(_ direction: ControllerConfig.FillDirection) -> String {
        switch direction {
        case .startToEnd: "from the start"
        case .endToStart: "from the end"
        case .centerOut: "from the center out"
        }
    }

    // MARK: Text

    /// `vehicle.engine_rpm` reads as "engine rpm".
    static func signalName(_ key: String) -> String {
        let trimmed = key.hasPrefix("vehicle.") ? String(key.dropFirst("vehicle.".count)) : key
        return trimmed
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    /// `left_turn` reads as "Left turn".
    static func humanize(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func format(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}
