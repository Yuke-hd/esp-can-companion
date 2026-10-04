import Foundation
import CompanionProtocol

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

    public var actions: [Action]

    public init(_ config: ControllerConfig) {
        actions = config.actions.map { action in
            Action(
                name: action.name,
                title: Self.humanize(action.name),
                triggers: config.rules.filter { $0.action == action.name }.map(Self.describe),
                outputs: config.outputs.filter { $0.action == action.name }.map(Self.describe)
            )
        }
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
