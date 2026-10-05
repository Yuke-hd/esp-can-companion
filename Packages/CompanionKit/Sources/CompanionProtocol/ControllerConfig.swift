import Foundation

/// Controller config, schema version 1 (firmware
/// `docs/specs/configuration/controller-config.md`).
///
/// `vehicle signal -> rule -> named action -> output binding`.
///
/// The app does not validate a config before upload: the controller is the
/// only validator, and its verdict comes back through Config status.
public struct ControllerConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var actions: [Action]
    public var rules: [Rule]
    public var outputs: [OutputBinding]

    public init(version: Int = 1, actions: [Action] = [], rules: [Rule] = [], outputs: [OutputBinding] = []) {
        self.version = version
        self.actions = actions
        self.rules = rules
        self.outputs = outputs
    }

    /// Decodes canonical (or any equivalent) config JSON.
    public init(canonicalJSON data: Data) throws {
        self = try JSONDecoder().decode(ControllerConfig.self, from: data)
    }

    /// Encodes the config as compact JSON with sorted keys, the same shape the
    /// controller's canonical serializer produces.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey {
        case version, actions, rules, outputs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        actions = try container.decodeIfPresent([Action].self, forKey: .actions) ?? []
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        outputs = try container.decodeIfPresent([OutputBinding].self, forKey: .outputs) ?? []
    }
}

extension ControllerConfig {
    public struct Action: Codable, Equatable, Sendable {
        /// Stable, unique name. Rules and outputs refer to actions by name.
        public var name: String

        public init(name: String) {
            self.name = name
        }
    }

    // MARK: Persisted names

    public enum Comparison: String, Codable, Equatable, Sendable, CaseIterable {
        case equal, notEqual = "not_equal", less, lessOrEqual = "less_or_equal"
        case greater, greaterOrEqual = "greater_or_equal"
    }

    /// Freshness a reading needs to count for a rule.
    public enum Freshness: String, Codable, Equatable, Sendable, CaseIterable {
        case fresh
        /// Also accepts readings whose signal has no freshness timeout. It
        /// never makes a reading fresh.
        case freshOrUnverified = "fresh_or_unverified"
    }

    public enum EventEdge: String, Codable, Equatable, Sendable, CaseIterable {
        case becomesTrue = "becomes_true", becomesFalse = "becomes_false"
    }

    public enum LedEffect: String, Codable, Equatable, Sendable, CaseIterable {
        case leftTurn = "left_turn", rightTurn = "right_turn", brake
    }

    public enum FillDirection: String, Codable, Equatable, Sendable, CaseIterable {
        case startToEnd = "start_to_end", endToStart = "end_to_start", centerOut = "center_out"
    }

    // MARK: Rules

    /// A rule operand, persisted as a one-key map such as `{"choice": "left"}`.
    public enum Operand: Codable, Equatable, Sendable {
        case boolean(Bool)
        case number(Double)
        /// One of the signal's enum choice keys.
        case choice(String)

        private enum CodingKeys: String, CodingKey {
            case boolean, number, choice
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.allKeys.count == 1, let key = container.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "An operand has exactly one of boolean, number or choice."
                ))
            }
            switch key {
            case .boolean: self = .boolean(try container.decode(Bool.self, forKey: key))
            case .number: self = .number(try container.decode(Double.self, forKey: key))
            case .choice: self = .choice(try container.decode(String.self, forKey: key))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .boolean(let value): try container.encode(value, forKey: .boolean)
            case .number(let value): try container.encode(value, forKey: .number)
            case .choice(let value): try container.encode(value, forKey: .choice)
            }
        }
    }

    /// The condition shared by `state`, `sampled_state` and `event` rules.
    public struct Condition: Equatable, Sendable {
        public var action: String
        public var signalKey: String
        public var comparison: Comparison
        public var operand: Operand
        public var freshness: Freshness

        public init(
            action: String,
            signalKey: String,
            comparison: Comparison,
            operand: Operand,
            freshness: Freshness = .fresh
        ) {
            self.action = action
            self.signalKey = signalKey
            self.comparison = comparison
            self.operand = operand
            self.freshness = freshness
        }
    }

    public struct Span: Codable, Equatable, Sendable {
        public var from: Double
        public var to: Double

        public init(from: Double, to: Double) {
            self.from = from
            self.to = to
        }
    }

    /// Maps a numeric signal linearly onto an output level range.
    public struct RangeRule: Equatable, Sendable {
        public var action: String
        public var signalKey: String
        public var input: Span
        public var output: Span
        public var freshness: Freshness

        public init(action: String, signalKey: String, input: Span, output: Span, freshness: Freshness = .fresh) {
            self.action = action
            self.signalKey = signalKey
            self.input = input
            self.output = output
            self.freshness = freshness
        }
    }

    public enum Rule: Codable, Equatable, Sendable {
        /// Level: on while the condition holds on notified readings.
        case state(Condition)
        /// Level, on sampled reads, with an optional hysteresis release value.
        case sampledState(Condition, releaseThreshold: Double? = nil)
        /// One-shot pulse on a condition edge.
        case event(Condition, edge: EventEdge)
        case range(RangeRule)

        public var action: String {
            switch self {
            case .state(let condition), .sampledState(let condition, _), .event(let condition, _):
                condition.action
            case .range(let rule):
                rule.action
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, action, signalKey = "signal_key", comparison, operand, freshness
            case releaseThreshold = "release_threshold", edge, input, output
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            let action = try container.decode(String.self, forKey: .action)
            let signalKey = try container.decode(String.self, forKey: .signalKey)
            let freshness = try container.decodeIfPresent(Freshness.self, forKey: .freshness) ?? .fresh
            func condition() throws -> Condition {
                Condition(
                    action: action,
                    signalKey: signalKey,
                    comparison: try container.decode(Comparison.self, forKey: .comparison),
                    operand: try container.decode(Operand.self, forKey: .operand),
                    freshness: freshness
                )
            }
            switch type {
            case "state":
                self = .state(try condition())
            case "sampled_state":
                self = .sampledState(
                    try condition(),
                    releaseThreshold: try container.decodeIfPresent(Double.self, forKey: .releaseThreshold)
                )
            case "event":
                self = .event(try condition(), edge: try container.decode(EventEdge.self, forKey: .edge))
            case "range":
                self = .range(RangeRule(
                    action: action,
                    signalKey: signalKey,
                    input: try container.decode(Span.self, forKey: .input),
                    output: try container.decode(Span.self, forKey: .output),
                    freshness: freshness
                ))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: container, debugDescription: "Unknown rule type \(type)."
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            func encode(_ condition: Condition, type: String) throws {
                try container.encode(type, forKey: .type)
                try container.encode(condition.action, forKey: .action)
                try container.encode(condition.signalKey, forKey: .signalKey)
                try container.encode(condition.comparison, forKey: .comparison)
                try container.encode(condition.operand, forKey: .operand)
                try container.encode(condition.freshness, forKey: .freshness)
            }
            switch self {
            case .state(let condition):
                try encode(condition, type: "state")
            case .sampledState(let condition, let releaseThreshold):
                try encode(condition, type: "sampled_state")
                try container.encodeIfPresent(releaseThreshold, forKey: .releaseThreshold)
            case .event(let condition, let edge):
                try encode(condition, type: "event")
                try container.encode(edge, forKey: .edge)
            case .range(let rule):
                try container.encode("range", forKey: .type)
                try container.encode(rule.action, forKey: .action)
                try container.encode(rule.signalKey, forKey: .signalKey)
                try container.encode(rule.input, forKey: .input)
                try container.encode(rule.output, forKey: .output)
                try container.encode(rule.freshness, forKey: .freshness)
            }
        }
    }

    // MARK: Output bindings

    public struct Zone: Codable, Equatable, Sendable {
        /// First logical pixel, from 0.
        public var start: Int
        public var length: Int
        public var direction: FillDirection

        /// Last logical pixel when the zone has a positive, representable length.
        public var lastPixel: Int? {
            guard length > 0 else { return nil }
            let (lastPixel, overflow) = start.addingReportingOverflow(length - 1)
            return overflow ? nil : lastPixel
        }

        public init(start: Int, length: Int, direction: FillDirection) {
            self.start = start
            self.length = length
            self.direction = direction
        }
    }

    public struct Color: Codable, Equatable, Sendable {
        public var red: Int
        public var green: Int
        public var blue: Int

        public init(red: Int, green: Int, blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// `led_effect`: binds the action to a discrete local LED effect.
    public struct EffectBinding: Equatable, Sendable {
        public var action: String
        public var effect: LedEffect
        public var priority: Int

        public init(action: String, effect: LedEffect, priority: Int = OutputBinding.defaultPriority) {
            self.action = action
            self.effect = effect
            self.priority = priority
        }
    }

    /// The fields `led_fill`, `led_transient` and `led_solid` share.
    public struct ZoneBinding: Equatable, Sendable {
        public var action: String
        public var zone: Zone
        public var color: Color
        public var priority: Int

        public init(action: String, zone: Zone, color: Color, priority: Int = OutputBinding.defaultPriority) {
            self.action = action
            self.zone = zone
            self.color = color
            self.priority = priority
        }
    }

    public enum OutputBinding: Codable, Equatable, Sendable {
        public static let defaultPriority = 100

        case ledEffect(EffectBinding)
        /// Fills part of the zone in proportion to the action's level.
        case ledFill(ZoneBinding)
        /// Lights the zone for `durationMs` after each trigger.
        case ledTransient(ZoneBinding, durationMs: Int)
        /// Lights the whole zone while the action is on.
        case ledSolid(ZoneBinding)

        public var action: String {
            switch self {
            case .ledEffect(let binding): binding.action
            case .ledFill(let binding), .ledTransient(let binding, _), .ledSolid(let binding): binding.action
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, action, effect, priority, zone, color, durationMs = "duration_ms"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            let action = try container.decode(String.self, forKey: .action)
            let priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? Self.defaultPriority
            func zoneBinding() throws -> ZoneBinding {
                ZoneBinding(
                    action: action,
                    zone: try container.decode(Zone.self, forKey: .zone),
                    color: try container.decode(Color.self, forKey: .color),
                    priority: priority
                )
            }
            switch type {
            case "led_effect":
                self = .ledEffect(EffectBinding(
                    action: action,
                    effect: try container.decode(LedEffect.self, forKey: .effect),
                    priority: priority
                ))
            case "led_fill":
                self = .ledFill(try zoneBinding())
            case "led_transient":
                self = .ledTransient(try zoneBinding(), durationMs: try container.decode(Int.self, forKey: .durationMs))
            case "led_solid":
                self = .ledSolid(try zoneBinding())
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: container, debugDescription: "Unknown output type \(type)."
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            func encode(_ binding: ZoneBinding, type: String) throws {
                try container.encode(type, forKey: .type)
                try container.encode(binding.action, forKey: .action)
                try container.encode(binding.zone, forKey: .zone)
                try container.encode(binding.color, forKey: .color)
                try container.encode(binding.priority, forKey: .priority)
            }
            switch self {
            case .ledEffect(let binding):
                try container.encode("led_effect", forKey: .type)
                try container.encode(binding.action, forKey: .action)
                try container.encode(binding.effect, forKey: .effect)
                try container.encode(binding.priority, forKey: .priority)
            case .ledFill(let binding):
                try encode(binding, type: "led_fill")
            case .ledTransient(let binding, let durationMs):
                try encode(binding, type: "led_transient")
                try container.encode(durationMs, forKey: .durationMs)
            case .ledSolid(let binding):
                try encode(binding, type: "led_solid")
            }
        }
    }
}
