import Foundation
import PresetSync
import CompanionProtocol

/// Editable presentation values. The controller owns semantic validation;
/// conversion only checks that numeric text can be represented in JSON.
struct RuleDraft {
    enum Kind: String, CaseIterable {
        case state, sampledState = "sampled_state", event, range
        var title: String { rawValue.replacingOccurrences(of: "_", with: " ").uppercased() }
    }

    enum OperandKind: String, CaseIterable { case boolean, number, choice }
    enum InputError: Error, Equatable { case number(String), wholeRPM(String), missingAction }

    var kind: Kind = .state
    var action: String
    var signalKey: String
    var comparison: ControllerConfig.Comparison = .equal
    var freshness: ControllerConfig.Freshness = .fresh
    var operandKind: OperandKind = .number
    var boolean = true
    var number = "0"
    var choice = ""
    var hasRelease = false
    var release = "0"
    var edge: ControllerConfig.EventEdge = .becomesTrue
    var inputFrom = "0"
    var inputTo = "6500"
    var outputFrom = "0"
    var outputTo = "1"

    init(_ rule: ControllerConfig.Rule) {
        action = rule.action
        signalKey = ""
        switch rule {
        case .state(let condition): load(condition)
        case .sampledState(let condition, let threshold):
            load(condition)
            kind = .sampledState
            hasRelease = threshold != nil
            release = threshold.map { SetupNumericEntry.formatted($0) } ?? "0"
        case .event(let condition, let edge):
            load(condition)
            kind = .event
            self.edge = edge
        case .range(let rule):
            kind = .range
            signalKey = rule.signalKey
            freshness = rule.freshness
            inputFrom = SetupNumericEntry.formatted(rule.input.from)
            inputTo = SetupNumericEntry.formatted(rule.input.to)
            outputFrom = SetupNumericEntry.formatted(rule.output.from)
            outputTo = SetupNumericEntry.formatted(rule.output.to)
        }
    }

    /// Uses a discovered signal's key and matches the operand to its catalog type.
    /// Unfamiliar types keep the current operand; the controller validates the rule.
    mutating func select(_ signal: SignalDescriptor) {
        signalKey = signal.key
        switch signal.type.known {
        case .boolean: operandKind = .boolean
        case .number: operandKind = .number
        case .enumeration:
            operandKind = .choice
            if !signal.choices.contains(where: { $0.key == choice }) { choice = signal.choices.first?.key ?? "" }
        case nil: break
        }
    }

    var availableFreshness: [ControllerConfig.Freshness] {
        signalKey == "vehicle.brake_pressed" ? [.freshOrUnverified] : ControllerConfig.Freshness.allCases
    }

    /// The action name as it will be saved; users may type any name.
    var actionName: String { action.trimmingCharacters(in: .whitespacesAndNewlines) }

    func makeRule() throws -> ControllerConfig.Rule {
        guard !actionName.isEmpty else { throw InputError.missingAction }
        switch kind {
        case .state: return .state(try condition())
        case .sampledState: return .sampledState(try condition(), releaseThreshold: hasRelease ? try signalNumber(release, field: "Release threshold") : nil)
        case .event: return .event(try condition(), edge: edge)
        case .range: return .range(try rangeRule())
        }
    }

    private var safeFreshness: ControllerConfig.Freshness {
        signalKey == "vehicle.brake_pressed" ? .freshOrUnverified : freshness
    }

    private func condition() throws -> ControllerConfig.Condition {
        .init(action: actionName, signalKey: signalKey, comparison: comparison, operand: try operand(), freshness: safeFreshness)
    }

    private func rangeRule() throws -> ControllerConfig.RangeRule {
        .init(
            action: actionName, signalKey: signalKey,
            input: .init(from: try signalNumber(inputFrom, field: "Input from"), to: try signalNumber(inputTo, field: "Input to")),
            output: .init(from: try numeric(outputFrom, field: "Output from"), to: try numeric(outputTo, field: "Output to")),
            freshness: safeFreshness
        )
    }

    private mutating func load(_ condition: ControllerConfig.Condition) {
        action = condition.action
        signalKey = condition.signalKey
        comparison = condition.comparison
        freshness = condition.freshness
        switch condition.operand {
        case .boolean(let value): operandKind = .boolean; boolean = value
        case .number(let value): operandKind = .number; number = SetupNumericEntry.formatted(value)
        case .choice(let value): operandKind = .choice; choice = value
        }
    }

    private func operand() throws -> ControllerConfig.Operand {
        switch operandKind {
        case .boolean: .boolean(boolean)
        case .number: .number(try signalNumber(number, field: "Operand"))
        case .choice: .choice(choice)
        }
    }

    private func numeric(_ text: String, field: String) throws -> Double {
        guard let value = Double(text), value.isFinite else { throw InputError.number(field) }
        return value
    }

    private func signalNumber(_ text: String, field: String) throws -> Double {
        let value = try numeric(text, field: field)
        if signalKey == "vehicle.engine_rpm", Int(text) == nil { throw InputError.wholeRPM(field) }
        return value
    }
}

extension ControllerConfig {
    /// Saves an edited rule, declaring its action when the user typed a new name.
    mutating func save(_ rule: Rule, at index: Int?) {
        if !actions.contains(where: { $0.name == rule.action }) { actions.append(Action(name: rule.action)) }
        if let index, rules.indices.contains(index) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }
}

/// What an output shows, as the effect editor offers it.
enum EffectKind: String, CaseIterable, Identifiable {
    case builtIn, fill, solid, flash
    var id: Self { self }
    var title: String {
        switch self {
        case .builtIn: "Built-in"
        case .fill: "Fill"
        case .solid: "Solid"
        case .flash: "Flash"
        }
    }
}

extension ControllerConfig.OutputBinding {
    static let defaultZone = ControllerConfig.Zone(start: 0, length: 10, direction: .startToEnd)
    static let defaultColor = ControllerConfig.Color(red: 32, green: 32, blue: 32)
    static let defaultFlashMs = 500

    static func solid(for action: String) -> Self {
        .ledSolid(.init(action: action, zone: defaultZone, color: defaultColor))
    }

    var effectKind: EffectKind {
        switch self {
        case .ledEffect: .builtIn
        case .ledFill: .fill
        case .ledSolid: .solid
        case .ledTransient: .flash
        case .unknown: .solid
        }
    }

    var priority: Int {
        switch self {
        case .ledEffect(let binding): binding.priority
        case .ledFill(let binding), .ledSolid(let binding), .ledTransient(let binding, _): binding.priority
        case .unknown: 0
        }
    }

    var zoneBinding: ControllerConfig.ZoneBinding? {
        switch self {
        case .ledEffect: nil
        case .ledFill(let binding), .ledSolid(let binding), .ledTransient(let binding, _): binding
        case .unknown: nil
        }
    }

    /// The same action and priority as another kind of output. Zone and colour
    /// carry over between fill, solid and flash.
    func converted(to kind: EffectKind) -> Self {
        guard kind != effectKind else { return self }
        let zone = zoneBinding ?? .init(action: action, zone: Self.defaultZone, color: Self.defaultColor, priority: priority)
        switch kind {
        case .builtIn: return .ledEffect(.init(action: action, effect: .brake, priority: priority))
        case .fill: return .ledFill(zone)
        case .solid: return .ledSolid(zone)
        case .flash: return .ledTransient(zone, durationMs: Self.defaultFlashMs)
        }
    }

    func replacingZone(_ binding: ControllerConfig.ZoneBinding) -> Self {
        switch self {
        case .ledEffect: self
        case .ledFill: .ledFill(binding)
        case .ledSolid: .ledSolid(binding)
        case .ledTransient(_, let durationMs): .ledTransient(binding, durationMs: durationMs)
        case .unknown: self
        }
    }

    func replacingPriority(_ priority: Int) -> Self {
        switch self {
        case .ledEffect(var binding):
            binding.priority = priority
            return .ledEffect(binding)
        default:
            guard var binding = zoneBinding else { return self }
            binding.priority = priority
            return replacingZone(binding)
        }
    }
}

extension ControllerConfig {
    /// Adds a rule with an action and output of its own, so its effect can be
    /// tuned without changing other rules. Returns the new rule's index.
    @discardableResult
    mutating func addCustomRule() -> Int {
        var number = 1
        while actions.contains(where: { $0.name == "custom_\(number)" }) { number += 1 }
        let action = "custom_\(number)"
        actions.append(.init(name: action))
        rules.append(.state(.init(action: action, signalKey: "vehicle.engine_rpm", comparison: .greaterOrEqual,
                                  operand: .number(6000), freshness: .freshOrUnverified)))
        outputs.append(.solid(for: action))
        return rules.count - 1
    }

    /// Removes a rule, and its action and outputs once no other rule uses them.
    mutating func removeRule(at index: Int) {
        guard rules.indices.contains(index) else { return }
        let action = rules.remove(at: index).action
        guard !rules.contains(where: { $0.action == action }) else { return }
        actions.removeAll { $0.name == action }
        outputs.removeAll { $0.action == action }
    }
}

extension ControllerConfig {
    enum RenameError: Error, Equatable {
        case empty, taken, reserved
    }

    /// Built-in actions are found by name for their inline controls and RPM
    /// checks, so they keep the names the app knows.
    static func isReservedAction(_ name: String) -> Bool {
        SetupAction(rawValue: name) != nil
    }

    /// The stored form of a typed action name: "Shift Light" becomes "shift_light".
    static func actionName(from text: String) -> String {
        let words = text.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.joined(separator: "_")
    }

    /// Renames an action along with every rule and output that uses it.
    mutating func renameAction(_ old: String, to text: String) throws {
        let name = Self.actionName(from: text)
        guard !name.isEmpty else { throw RenameError.empty }
        guard name != old else { return }
        guard !actions.contains(where: { $0.name == name }) else { throw RenameError.taken }
        guard !Self.isReservedAction(old), !Self.isReservedAction(name) else { throw RenameError.reserved }
        for index in actions.indices where actions[index].name == old { actions[index].name = name }
        rules = rules.map { $0.renamingAction(to: name, from: old) }
        outputs = outputs.map { $0.action == old ? $0.renamingAction(to: name) : $0 }
    }
}

extension ControllerConfig.Rule {
    func renamingAction(to name: String, from old: String) -> Self {
        guard action == old else { return self }
        switch self {
        case .state(var condition):
            condition.action = name
            return .state(condition)
        case .sampledState(var condition, let release):
            condition.action = name
            return .sampledState(condition, releaseThreshold: release)
        case .event(var condition, let edge):
            condition.action = name
            return .event(condition, edge: edge)
        case .range(var rule):
            rule.action = name
            return .range(rule)
        }
    }
}

extension ControllerConfig.OutputBinding {
    func renamingAction(to name: String) -> Self {
        switch self {
        case .ledEffect(var binding):
            binding.action = name
            return .ledEffect(binding)
        case .unknown(let value):
            guard var object = value.object, object["action"]?.stringValue == action else { return self }
            object["action"] = .string(name)
            return .unknown(.object(object))
        default:
            guard var binding = zoneBinding else { return self }
            binding.action = name
            return replacingZone(binding)
        }
    }
}
