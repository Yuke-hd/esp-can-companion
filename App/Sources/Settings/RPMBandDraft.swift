import CompanionLink

/// What the Gauges page's RPM fields hold while being edited. Only a draft
/// that parses and passes `RPMBand.issue` becomes the live band.
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

    init(_ band: RPMBand) {
        let fill = band.fill ?? AppConfig.default.rpmBand.fill!
        fillFrom = SetupNumericEntry.formatted(fill.from)
        fillTo = SetupNumericEntry.formatted(fill.to)
        redlineOn = band.redline != nil
        let fallback = min(AppConfig.default.rpmBand.redline ?? fill.to, fill.to)
        redline = SetupNumericEntry.formatted(band.redline ?? fallback)
    }

    var result: Result<RPMBand, Problem> {
        func number(_ text: String) -> Double? { SetupNumericEntry.parse(text, integerOnly: true) }
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
