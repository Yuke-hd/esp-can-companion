import CompanionProtocol

/// The RPM span the in-app displays (shift lights, RPM bar, drive numeral)
/// are drawn against. This belongs to the app, not the controller: it never
/// follows the config the controller is running.
public struct RPMBand: Equatable, Sendable {
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
public struct AppConfig: Equatable, Sendable {
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
