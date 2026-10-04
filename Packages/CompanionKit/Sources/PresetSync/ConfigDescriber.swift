import Foundation
import CompanionProtocol

/// One action of a config and what it does.
public struct ActionDescription: Equatable, Sendable, Identifiable {
    /// The persisted action name.
    public var id: String
    /// The action name for display, such as "Red zone".
    public var title: String
    /// What the action does, as one or two sentences.
    public var detail: String
}

/// Describes a config's actions in plain language: what lights up, and when.
public enum ConfigDescriber {
    public static func describe(_ config: ControllerConfig) -> [ActionDescription] {
        config.actions.map { action in
            let rules = config.rules.filter { $0.action == action.name }
            let outputs = config.outputs.filter { $0.action == action.name }
            return ActionDescription(
                id: action.name,
                title: title(action.name),
                detail: detail(rules: rules, outputs: outputs)
            )
        }
    }

    static func title(_ name: String) -> String {
        let words = name.split(separator: "_").map { word in
            word == "rpm" ? "RPM" : String(word)
        }
        let joined = words.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    static func detail(rules: [ControllerConfig.Rule], outputs: [ControllerConfig.OutputBinding]) -> String {
        let what = outputs.isEmpty ? "Shows nothing" : sentenceCase(list(outputs.map(phrase), conjunction: "and"))
        guard !rules.isEmpty else { return "\(what). No rule turns it on." }
        var text = "\(what) \(list(rules.map(phrase), conjunction: "or"))."
        if rules.contains(where: { freshness(of: $0) == .freshOrUnverified }) {
            text += " It also acts on readings the controller cannot confirm are fresh."
        }
        return text
    }

    static func freshness(of rule: ControllerConfig.Rule) -> ControllerConfig.Freshness {
        switch rule {
        case .state(let condition), .sampledState(let condition, _), .event(let condition, _): condition.freshness
        case .range(let range): range.freshness
        }
    }

    // MARK: Outputs

    static func phrase(_ output: ControllerConfig.OutputBinding) -> String {
        switch output {
        case .ledEffect(let binding):
            return "runs the \(effect(binding.effect)) LED effect"
        case .ledFill(let binding):
            return "fills \(pixels(binding.zone)) \(direction(binding.zone.direction)) in \(colorName(binding.color))"
        case .ledTransient(let binding, let durationMs):
            return "lights \(pixels(binding.zone)) \(colorName(binding.color)) for \(durationMs) ms"
        case .ledSolid(let binding):
            return "lights \(pixels(binding.zone)) solid \(colorName(binding.color))"
        }
    }

    static func effect(_ effect: ControllerConfig.LedEffect) -> String {
        switch effect {
        case .leftTurn: "left-turn"
        case .rightTurn: "right-turn"
        case .brake: "brake"
        }
    }

    static func pixels(_ zone: ControllerConfig.Zone) -> String {
        zone.length == 1 ? "pixel \(zone.start)" : "pixels \(zone.start)–\(zone.start + zone.length - 1)"
    }

    static func direction(_ direction: ControllerConfig.FillDirection) -> String {
        switch direction {
        case .startToEnd: "from the start"
        case .endToStart: "from the end"
        case .centerOut: "from the centre out"
        }
    }

    /// A coarse colour name from the hue, such as "red" or "blue".
    static func colorName(_ color: ControllerConfig.Color) -> String {
        let red = Double(color.red), green = Double(color.green), blue = Double(color.blue)
        let maximum = max(red, green, blue), minimum = min(red, green, blue)
        guard maximum > 0 else { return "black (off)" }
        guard (maximum - minimum) / maximum > 0.2 else { return "white" }
        let delta = maximum - minimum
        var hue: Double
        if maximum == red {
            hue = 60 * ((green - blue) / delta)
        } else if maximum == green {
            hue = 60 * ((blue - red) / delta + 2)
        } else {
            hue = 60 * ((red - green) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        switch hue {
        case ..<15: return "red"
        case ..<45: return "orange"
        case ..<70: return "yellow"
        case ..<160: return "green"
        case ..<195: return "cyan"
        case ..<250: return "blue"
        case ..<290: return "purple"
        case ..<340: return "pink"
        default: return "red"
        }
    }

    // MARK: Rules

    static func phrase(_ rule: ControllerConfig.Rule) -> String {
        switch rule {
        case .state(let condition):
            return "while \(phrase(condition))"
        case .sampledState(let condition, let releaseThreshold):
            let base = "while \(phrase(condition))"
            guard let releaseThreshold else { return base }
            return "\(base), until it drops back past \(number(releaseThreshold, signal: condition.signalKey))"
        case .event(let condition, let edge):
            switch edge {
            case .becomesTrue: return "briefly each time \(phrase(condition)) starts to hold"
            case .becomesFalse: return "briefly each time \(phrase(condition)) stops holding"
            }
        case .range(let rule):
            let signal = Signal(rule.signalKey)
            return "in proportion to \(signal.label) from \(number(rule.input.from, signal: rule.signalKey)) "
                + "to \(number(rule.input.to, signal: rule.signalKey))"
        }
    }

    static func phrase(_ condition: ControllerConfig.Condition) -> String {
        let signal = Signal(condition.signalKey)
        switch condition.operand {
        case .boolean(let value):
            let holds: Bool
            switch condition.comparison {
            case .equal: holds = value
            case .notEqual: holds = !value
            default: return "\(signal.label) is \(comparison(condition.comparison)) \(value)"
            }
            return "\(signal.label) \(holds ? signal.whenTrue : signal.whenFalse)"
        case .choice(let choice):
            let verb = condition.comparison == .notEqual ? "is not" : "is"
            return "\(signal.label) \(verb) \(signal.choiceLabel(choice))"
        case .number(let value):
            return "\(signal.label) is \(comparison(condition.comparison)) \(number(value, signal: condition.signalKey))"
        }
    }

    static func comparison(_ comparison: ControllerConfig.Comparison) -> String {
        switch comparison {
        case .equal: "exactly"
        case .notEqual: "not"
        case .less: "below"
        case .lessOrEqual: "at most"
        case .greater: "above"
        case .greaterOrEqual: "at least"
        }
    }

    static func number(_ value: Double, signal key: String) -> String {
        let formatted = value.rounded() == value && abs(value) < 1e9 ? grouped(Int(value)) : String(value)
        guard let unit = Signal(key).unit else { return formatted }
        return "\(formatted) \(unit)"
    }

    /// The signals the bundled presets use, with readable names. Any other
    /// key is shown as is.
    struct Signal {
        var label: String
        var unit: String?
        var whenTrue = "is true"
        var whenFalse = "is false"
        var choices: [String: String] = [:]

        init(_ key: String) {
            switch key {
            case "vehicle.turn_state":
                label = "the turn signal"
                choices = ["left": "left", "right": "right", "hazard": "on hazards"]
            case "vehicle.engine_rpm":
                label = "engine speed"
                unit = "rpm"
            case "vehicle.brake_pressed":
                label = "the brake pedal"
                whenTrue = "is pressed"
                whenFalse = "is released"
            default:
                label = key
            }
        }

        func choiceLabel(_ choice: String) -> String {
            choices[choice] ?? choice
        }
    }

    // MARK: Text

    static func list(_ items: [String], conjunction: String) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) \(conjunction) \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", \(conjunction) \(items.last!)"
        }
    }

    /// `6500` as `6,500`, independent of the locale, to match the summaries.
    static func grouped(_ value: Int) -> String {
        var digits = String(value.magnitude)
        var index = digits.endIndex
        while digits.distance(from: digits.startIndex, to: index) > 3 {
            index = digits.index(index, offsetBy: -3)
            digits.insert(",", at: index)
        }
        return value < 0 ? "-" + digits : digits
    }

    static func sentenceCase(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
