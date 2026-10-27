import CompanionLink

import Foundation

/// What the Gauges page's RPM fields hold while being edited. Edits reach the
/// live band only on commit (see `commit()`), and only when the draft parses
/// and passes `RPMBand.issue`.
struct RPMBandDraft: Equatable {
    enum Field: Hashable {
        case fillFrom, fillTo, redline
    }

    enum Problem: Error, Equatable {
        case notAWholeNumber(Field)
        case rule(RPMBandIssue)
    }

    var fillFrom: String
    var fillTo: String
    var redlineOn: Bool
    /// Kept while the redline is off, so turning it back on restores it.
    var redline: String

    /// Used when a band has no fill; matches `AppConfig.default`.
    private static let fallbackFill = AppConfig.default.rpmBand.fill ?? .init(from: 0, to: 6500)

    init(_ band: RPMBand) {
        let fill = band.fill ?? Self.fallbackFill
        fillFrom = SetupNumericEntry.formatted(fill.from)
        fillTo = SetupNumericEntry.formatted(fill.to)
        redlineOn = band.redline != nil
        let fallback = min(AppConfig.default.rpmBand.redline ?? fill.to, fill.to)
        redline = SetupNumericEntry.formatted(band.redline ?? fallback)
    }

    var result: Result<RPMBand, Problem> {
        func number(_ text: String) -> Double? { Self.wholeNumber(text) }
        guard let from = number(fillFrom) else { return .failure(.notAWholeNumber(.fillFrom)) }
        guard let to = number(fillTo) else { return .failure(.notAWholeNumber(.fillTo)) }
        var redlineValue: Double?
        if redlineOn {
            guard let value = number(redline) else { return .failure(.notAWholeNumber(.redline)) }
            redlineValue = value
        }
        let band = RPMBand(fill: .init(from: from, to: to), redline: redlineValue)
        if let issue = band.issue { return .failure(.rule(issue)) }
        return .success(band)
    }

    var problem: Problem? {
        if case .failure(let problem) = result { return problem }
        return nil
    }

    /// The commit rule: a valid draft gives the band to apply and its fields
    /// are shown as canonical numbers (`06000` becomes `6000`); an invalid one
    /// gives the problem and is left as typed, so the last committed band
    /// stays live. The hidden redline text is kept while the redline is off.
    mutating func commit() -> Result<RPMBand, Problem> {
        let result = result
        if case .success(let band) = result, let fill = band.fill {
            fillFrom = SetupNumericEntry.formatted(fill.from)
            fillTo = SetupNumericEntry.formatted(fill.to)
            if let redline = band.redline { self.redline = SetupNumericEntry.formatted(redline) }
        }
        return result
    }

    /// An optionally signed run of digits, ignoring surrounding whitespace.
    /// Digits too long for `Int` still parse, so they meet the range rules
    /// instead of being called "not a whole number".
    static func wholeNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.first.map { "+-".contains($0) } == true ? trimmed.dropFirst() : Substring(trimmed)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Double(trimmed).flatMap { $0.isFinite ? $0 : nil }
    }
}

extension AppModel {
    /// Commits the Gauges draft: applies its band when valid, otherwise keeps
    /// the live band and returns why.
    @discardableResult
    func commitRPMBand(_ draft: inout RPMBandDraft) -> RPMBandDraft.Problem? {
        switch draft.commit() {
        case .success(let band): return setRPMBand(band).map { .rule($0) }
        case .failure(let problem): return problem
        }
    }
}

extension RPMBandDraft.Problem {
    /// The inline message under the RPM fields.
    var message: String {
        switch self {
        case .notAWholeNumber(.fillFrom): "Enter fill start as a whole number of rpm."
        case .notAWholeNumber(.fillTo): "Enter fill end as a whole number of rpm."
        case .notAWholeNumber(.redline): "Enter the redline as a whole number of rpm."
        case .rule(.missingFill): "Enter a fill start and end."
        case .rule(.fillStartBelowZero): "Fill start must be 0 rpm or more."
        case .rule(.fillEndAboveMaximum): "Fill end must be \(SetupNumericEntry.formatted(RPMBand.maximumRPM)) rpm or less."
        case .rule(.fillStartNotBelowEnd): "Fill start must be below fill end."
        case .rule(.redlineNotAboveFillStart): "Redline must be above fill start."
        case .rule(.redlineAboveFillEnd): "Redline must be at or below fill end."
        }
    }
}

extension RPMBand {
    /// The Gauges row's value on the settings top level.
    var settingsSummary: String {
        redline.map { "Redline \(SetupNumericEntry.formatted($0))" } ?? "Redline off"
    }
}
