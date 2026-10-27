import CompanionProtocol

/// The RPM span the in-app displays (shift lights, RPM bar, drive numeral)
/// are drawn against. This belongs to the app, not the controller: it never
/// follows the config the controller is running.
public struct RPMBand: Codable, Equatable, Sendable {
    /// The span the shift lights fill across.
    public var fill: ControllerConfig.Span?
    /// The RPM at which the displays turn red.
    public var redline: Double?

    public init(fill: ControllerConfig.Span?, redline: Double?) {
        self.fill = fill
        self.redline = redline
    }
}

/// Settings of the app itself, independent of the connected controller.
public struct AppConfig: Codable, Equatable, Sendable {
    public var rpmBand: RPMBand
    /// The rounded display span for brake pressure. This is a visual scale,
    /// not a vehicle limit or a claim about the controller's 91.071 bar
    /// encoding ceiling.
    public var brakePressureBarScale: Double

    public init(rpmBand: RPMBand, brakePressureBarScale: Double = 70) {
        self.rpmBand = rpmBand
        self.brakePressureBarScale = brakePressureBarScale
    }

    public static let `default` = AppConfig(
        rpmBand: RPMBand(fill: .init(from: 0, to: 6500), redline: 6000),
        brakePressureBarScale: 70
    )
}

/// A rule an `RPMBand` breaks. Each has its own case so the app can say
/// exactly what to fix.
public enum RPMBandIssue: Error, Equatable, Sendable {
    /// The band has no fill span.
    case missingFill
    /// The fill starts below 0 RPM.
    case fillStartBelowZero
    /// The fill ends above `RPMBand.maximumRPM`.
    case fillEndAboveMaximum
    /// The fill does not start below where it ends.
    case fillStartNotBelowEnd
    /// The redline is at or below the fill start.
    case redlineNotAboveFillStart
    /// The redline is above the fill end.
    case redlineAboveFillEnd
}

extension RPMBand {
    /// The highest RPM a band may reach.
    public static let maximumRPM: Double = 12_000

    /// The first rule this band breaks, or nil when it is valid:
    /// `0 ≤ fill.from < fill.to ≤ maximumRPM`, and the redline is off or
    /// `fill.from < redline ≤ fill.to`. Comparisons are written so NaN fails.
    public var issue: RPMBandIssue? {
        guard let fill else { return .missingFill }
        guard fill.from >= 0 else { return .fillStartBelowZero }
        guard fill.to <= Self.maximumRPM else { return .fillEndAboveMaximum }
        guard fill.from < fill.to else { return .fillStartNotBelowEnd }
        if let redline {
            guard redline > fill.from else { return .redlineNotAboveFillStart }
            guard redline <= fill.to else { return .redlineAboveFillEnd }
        }
        return nil
    }
}

extension AppConfig {
    /// This config, with an invalid RPM band replaced by the default band.
    public var withValidRPMBand: AppConfig {
        guard rpmBand.issue != nil else { return self }
        var config = self
        config.rpmBand = AppConfig.default.rpmBand
        return config
    }
}
