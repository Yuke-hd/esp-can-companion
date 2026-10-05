import Foundation
import CompanionProtocol

/// Editable presentation values. The controller owns semantic validation;
/// conversion only checks that numeric text can be represented in JSON.
struct RuleDraft {
    enum Kind: String, CaseIterable {
        case state, sampledState = "sampled_state", event, range
        var title: String { rawValue.replacingOccurrences(of: "_", with: " ").uppercased() }
    }

    enum OperandKind: String, CaseIterable { case boolean, number, choice }
    enum InputError: Error, Equatable { case number(String), wholeRPM(String) }

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

    var availableFreshness: [ControllerConfig.Freshness] {
        signalKey == "vehicle.brake_pressed" ? [.freshOrUnverified] : ControllerConfig.Freshness.allCases
    }

    func makeRule() throws -> ControllerConfig.Rule {
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
        .init(action: action, signalKey: signalKey, comparison: comparison, operand: try operand(), freshness: safeFreshness)
    }

    private func rangeRule() throws -> ControllerConfig.RangeRule {
        .init(
            action: action, signalKey: signalKey,
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
