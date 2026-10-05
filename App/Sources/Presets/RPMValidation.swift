import CompanionProtocol

/// Local editing checks; the controller still validates the complete configuration on send.
enum RPMValidation {
    static let allowedRange = 0.0...12000.0

    struct Issue: Equatable, Identifiable {
        enum Field: String {
            case inputFrom, inputTo, trigger, release
            var label: String {
                switch self {
                case .inputFrom: "Minimum RPM"
                case .inputTo: "Maximum RPM"
                case .trigger: "Trigger RPM"
                case .release: "Release RPM"
                }
            }
        }

        enum Problem: Equatable {
            case outsideBounds, fractional, rangeOrder, releaseOrder, redLineOrder
            var message: String {
                switch self {
                case .outsideBounds: "RPM must be between 0 and 12,000."
                case .fractional: "RPM must be a whole number."
                case .rangeOrder: "Minimum RPM must be lower than maximum RPM."
                case .releaseOrder: "Release RPM must be lower than trigger RPM."
                case .redLineOrder: "Red-line RPM must be lower than maximum RPM."
                }
            }
        }

        let ruleIndex: Int
        let field: Field
        let problem: Problem
        var id: String { "\(ruleIndex).\(field.rawValue)" }
        var message: String { problem.message }
        var summary: String { "\(field.label): \(message)" }
    }

    static func issues(in config: ControllerConfig) -> [Issue] {
        let maximum = config.rules.compactMap { rule -> Double? in
            guard case .range(let range) = rule, range.action == "rpm_fill",
                  range.signalKey == "vehicle.engine_rpm", problem(for: range.input.to) == nil else { return nil }
            return range.input.to
        }.min()
        return config.rules.enumerated().flatMap { index, rule in
            switch rule {
            case .range(let range): return rangeIssues(range, index: index)
            case .state(let condition), .event(let condition, _):
                return conditionIssues(condition, release: nil, index: index, maximum: maximum)
            case .sampledState(let condition, let release):
                return conditionIssues(condition, release: release, index: index, maximum: maximum)
            }
        }
    }

    private static func rangeIssues(_ range: ControllerConfig.RangeRule, index: Int) -> [Issue] {
        guard range.signalKey == "vehicle.engine_rpm" else { return [] }
        var issues = valueIssues(range.input.from, field: .inputFrom, index: index)
            + valueIssues(range.input.to, field: .inputTo, index: index)
        if issues.isEmpty && range.input.from >= range.input.to {
            issues.append(.init(ruleIndex: index, field: .inputTo, problem: .rangeOrder))
        }
        return issues
    }

    private static func conditionIssues(_ condition: ControllerConfig.Condition, release: Double?,
                                        index: Int, maximum: Double?) -> [Issue] {
        guard condition.signalKey == "vehicle.engine_rpm" else { return [] }
        var issues = release.map { valueIssues($0, field: .release, index: index) } ?? []
        guard case .number(let trigger) = condition.operand else { return issues }
        issues += valueIssues(trigger, field: .trigger, index: index)
        guard problem(for: trigger) == nil else { return issues }
        if condition.action == "red_zone", let maximum, trigger >= maximum {
            issues.append(.init(ruleIndex: index, field: .trigger, problem: .redLineOrder))
        }
        if let release, problem(for: release) == nil,
           (condition.action == "red_zone" || condition.comparison == .greater || condition.comparison == .greaterOrEqual),
           release >= trigger {
            issues.append(.init(ruleIndex: index, field: .release, problem: .releaseOrder))
        }
        return issues
    }

    private static func valueIssues(_ value: Double, field: Issue.Field, index: Int) -> [Issue] {
        guard let problem = problem(for: value) else { return [] }
        return [.init(ruleIndex: index, field: field, problem: problem)]
    }

    private static func problem(for value: Double) -> Issue.Problem? {
        guard value.isFinite && allowedRange.contains(value) else { return .outsideBounds }
        return value.rounded() == value ? nil : .fractional
    }
}
