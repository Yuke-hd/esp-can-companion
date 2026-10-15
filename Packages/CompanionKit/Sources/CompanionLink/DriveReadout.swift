import Foundation
import BLETransport
import CompanionProtocol

/// The values shared by both Drive layouts. This model keeps signal
/// availability and config-derived RPM presentation out of SwiftUI.
public struct DriveReadout: Equatable, Sendable {
    /// Whether the configured RPM red zone is currently active.
    public enum RedlineState: Equatable, Sendable {
        case standby
        case active
    }

    /// The non-live status values shown alongside the Drive telemetry.
    public struct Status: Equatable, Sendable {
        public var linkState: LinkState
        public var telemetryStarted: Bool?
        public var frameRate: Int
        public var profileName: String?
        public var doors: PitWallReadout.Tile
        public var lock: PitWallReadout.Tile
        public var hazard: PitWallReadout.Tile

        public init(
            linkState: LinkState,
            telemetryStarted: Bool?,
            frameRate: Int,
            profileName: String?,
            doors: PitWallReadout.Tile,
            lock: PitWallReadout.Tile,
            hazard: PitWallReadout.Tile
        ) {
            self.linkState = linkState
            self.telemetryStarted = telemetryStarted
            self.frameRate = frameRate
            self.profileName = profileName
            self.doors = doors
            self.lock = lock
            self.hazard = hazard
        }
    }

    /// Pit Wall's readout is the single source for gear text, freshness,
    /// turn/hazard tile wording and RPM scaling.
    private let pitWall: PitWallReadout
    private let brakePressureScaleBar: Double
    public let selector: String?
    public let selectorFreshness: PitWallReadout.Freshness
    public let redlineState: RedlineState
    public let status: Status
    /// Throttle and brake pressure come from the extensible signal snapshot;
    /// the fixed legacy frame has neither signal. Boost remains unsupported.
    public let throttle: PitWallReadout.Tile
    public let brakePressure: PitWallReadout.Tile
    public let boost: PitWallReadout.Tile
    /// Normalized accelerator position, when the extensible signal is live or
    /// freshness-unverified. The controller contract publishes `0...1`.
    public let throttleFraction: Double?
    /// Brake pressure in the controller's bar presentation, when available.
    public let brakePressureBar: Double?
    /// Acceleration in g, only when both axes are fresh with values. Nil
    /// otherwise, never zero: a lone axis would put the g-meter dot in the
    /// wrong place, and layout 1 or a stalled stream has no acceleration.
    public let acceleration: GForce?
    public let longitudinalAccelerationFreshness: PitWallReadout.Freshness
    public let lateralAccelerationFreshness: PitWallReadout.Freshness

    /// Builds the Drive readout from one frame and the active controller
    /// summary. `linkState` and `framesPerSecond` are supplied by the owning
    /// session; neither is inferred from signal timing here.
    public init(
        frame: LiveSignalFrame,
        activeConfig: ConfigSummary? = nil,
        rpmBand band: RPMBand? = nil,
        snapshot: ExtensibleSignalSnapshot? = nil,
        brakePressureBarScale: Double = AppConfig.default.brakePressureBarScale,
        linkState: LinkState = .unknown,
        framesPerSecond: Int = 0
    ) {
        let pitWall = PitWallReadout(frame: frame, band: band)
        self.pitWall = pitWall
        self.brakePressureScaleBar = Self.validBrakePressureScale(brakePressureBarScale)

        selectorFreshness = PitWallReadout.Freshness(frame.selectorPosition.availability)
        selector = selectorFreshness.showsValue
            ? frame.selectorPosition.value.map(Self.selectorText)
            : nil

        redlineState = Self.redlineState(rpm: pitWall.rpm, threshold: band?.redline)

        let tiles = Dictionary(uniqueKeysWithValues: pitWall.tiles.map { ($0.title, $0) })
        let doors = Self.tile(named: "Doors", in: tiles)
        let lock = Self.tile(named: "Lock", in: tiles)
        let hazard = Self.tile(named: "Hazard", in: tiles)
        status = Status(
            linkState: linkState,
            telemetryStarted: pitWall.isTelemetryStarted,
            frameRate: frame == .unknown ? 0 : framesPerSecond,
            profileName: activeConfig.map(Self.profileName),
            doors: doors,
            lock: lock,
            hazard: hazard
        )

        let unsupported = frame == .unknown ? PitWallReadout.Freshness.unknown : .unsupported
        let sideSignals = Self.sideSignals(snapshot: snapshot, frame: frame)
        throttle = sideSignals.throttle.tile
        throttleFraction = sideSignals.throttle.value
        brakePressure = sideSignals.brakePressure.tile
        brakePressureBar = sideSignals.brakePressure.value
        boost = Self.placeholder(title: "Boost", freshness: unsupported)

        let longitudinal = frame.longitudinalAcceleration
        let lateral = frame.lateralAcceleration
        longitudinalAccelerationFreshness = PitWallReadout.Freshness(longitudinal.availability)
        lateralAccelerationFreshness = PitWallReadout.Freshness(lateral.availability)
        if longitudinal.isLive, lateral.isLive,
           let longitudinalValue = longitudinal.value, let lateralValue = lateral.value {
            acceleration = GForce(
                longitudinalMetersPerSecondSquared: longitudinalValue,
                lateralMetersPerSecondSquared: lateralValue
            )
        } else {
            acceleration = nil
        }
    }

    // MARK: Live aliases

    public var rpm: Double? { rpmFreshness.showsValue ? pitWall.rpm : nil }
    /// RPM has no controller freshness timeout, so even a malformed frame
    /// claiming `Fresh` remains labelled unverified in Drive.
    public var rpmFreshness: PitWallReadout.Freshness {
        pitWall.rpmFreshness == .fresh ? .unverified : pitWall.rpmFreshness
    }
    public var gear: String? { pitWall.gear }
    public var gearFreshness: PitWallReadout.Freshness { pitWall.gearFreshness }
    public var speedKPH: Int? { pitWall.speedKPH }
    public var speedFreshness: PitWallReadout.Freshness { pitWall.speedFreshness }
    public var litShiftLights: Int { pitWall.litShiftLights }
    public var firstRedShiftLight: Int? { pitWall.firstRedShiftLight }
    public var rpmFraction: Double { pitWall.rpmFraction }
    public var redlineFraction: Double? { pitWall.redlineFraction }
    public var brake: PitWallReadout.Tile { Self.tile(named: "Brake", in: pitWall.tiles) }
    public var turn: PitWallReadout.Tile { Self.tile(named: "Turn", in: pitWall.tiles) }
    public var doors: PitWallReadout.Tile { status.doors }
    public var lock: PitWallReadout.Tile { status.lock }
    public var hazard: PitWallReadout.Tile { status.hazard }

    /// Accelerator position as a percentage for the Drive captions.
    public var throttlePercent: Double? { throttleFraction.map { $0 * 100 } }
    public var throttleFreshness: PitWallReadout.Freshness { throttle.freshness }
    /// Brake pressure as a percentage of the configured visual scale.
    public var brakePressurePercent: Double? { brakePressureFraction.map { $0 * 100 } }
    /// Fill fraction for the brake pressure bar. The scale is configurable
    /// and is deliberately a rounded visual span, not a vehicle limit.
    public var brakePressureFraction: Double? {
        guard let brakePressureBar else { return nil }
        return min(brakePressureBar, brakePressureScaleBar) / brakePressureScaleBar
    }
    public var brakePressureFreshness: PitWallReadout.Freshness { brakePressure.freshness }
    public var boostValue: Double? { nil }
    public var boostFreshness: PitWallReadout.Freshness { boost.freshness }

    // MARK: Status aliases

    public var linkState: LinkState { status.linkState }
    public var telemetryStarted: Bool? { status.telemetryStarted }
    public var isTelemetryStarted: Bool? { telemetryStarted }
    public var framesPerSecond: Int { status.frameRate }
    public var activeProfileName: String? { status.profileName }
    public var signalTiles: [PitWallReadout.Tile] { [brake, turn, hazard, doors, lock] }
    public var redlineActive: Bool { redlineState == .active }
    public var isRedlineActive: Bool { redlineActive }

    // MARK: Mapping

    private static func tile(named title: String, in tiles: [PitWallReadout.Tile]) -> PitWallReadout.Tile {
        tile(named: title, in: Dictionary(uniqueKeysWithValues: tiles.map { ($0.title, $0) }))
    }

    private static func tile(named title: String, in tiles: [String: PitWallReadout.Tile]) -> PitWallReadout.Tile {
        tiles[title] ?? placeholder(title: title, freshness: .unknown)
    }

    private static func placeholder(title: String, freshness: PitWallReadout.Freshness) -> PitWallReadout.Tile {
        PitWallReadout.Tile(title: title, value: nil, tone: .muted, freshness: freshness)
    }

    private static func numberTile(
        title: String,
        reading: SignalReading<Double>?,
        format: (Double) -> String
    ) -> (tile: PitWallReadout.Tile, value: Double?) {
        guard let reading else {
            return (placeholder(title: title, freshness: .unsupported), nil)
        }
        let freshness = PitWallReadout.Freshness(reading.availability)
        guard freshness.showsValue, let value = reading.value else {
            return (placeholder(title: title, freshness: freshness), nil)
        }
        return (
            PitWallReadout.Tile(title: title, value: format(value), tone: .normal, freshness: freshness),
            value
        )
    }

    private static func sideSignals(
        snapshot: ExtensibleSignalSnapshot?,
        frame: LiveSignalFrame
    ) -> (
        throttle: (tile: PitWallReadout.Tile, value: Double?),
        brakePressure: (tile: PitWallReadout.Tile, value: Double?)
    ) {
        let fallback: SignalAvailability = frame == .unknown ? .unknown : .notSupported
        let accelerator = number(
            key: "vehicle.accelerator_pedal_position", unit: "none", snapshot: snapshot,
            range: 0...1
        )
        var pressure = number(
            key: "vehicle.brake_pressure", unit: "none", snapshot: snapshot,
            range: -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude
        )
        if let value = pressure?.value {
            pressure?.value = max(0, value)
        }
        let throttle = accelerator ?? .init(availability: fallback, value: nil)
        let brake = pressure ?? .init(availability: fallback, value: nil)
        return (
            numberTile(title: "Throttle", reading: throttle) {
                String(format: "%.0f%%", $0 * 100)
            },
            numberTile(title: "Brake pressure", reading: brake) {
                String(format: "%.1f bar", $0)
            }
        )
    }

    private static func number(
        key: String,
        unit: String,
        snapshot: ExtensibleSignalSnapshot?,
        range: ClosedRange<Double>
    ) -> SignalReading<Double>? {
        guard let snapshot else { return nil }
        guard !snapshot.isStalled else { return .unknown }
        guard let state = snapshot.signals.first(where: {
            $0.descriptor.key.utf8.elementsEqual(key.utf8)
        }) else {
            return snapshot.catalog == nil ? nil : .init(availability: .notSupported, value: nil)
        }
        guard state.descriptor.type.known == .number, state.descriptor.unit == unit else {
            return .unknown
        }
        let availability = state.reading.availability
        guard let value = state.reading.value else {
            return .init(availability: availability, value: nil)
        }
        guard case .number(let number) = value, number.isFinite,
              range.contains(Double(number)) else {
            return .unknown
        }
        return .init(availability: availability, value: Double(number))
    }

    private static func validBrakePressureScale(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : AppConfig.default.brakePressureBarScale
    }

    private static func redlineState(rpm: Double?, threshold: Double?) -> RedlineState {
        guard let rpm, let threshold, rpm >= threshold else { return .standby }
        return .active
    }

    private static func selectorText(_ selector: WireValue<SelectorPosition>) -> String {
        guard case .known(let selector) = selector else { return "?" }
        return switch selector {
        case .unknown: "?"
        case .shifting: "Shift"
        case .park: "P"
        case .reverse: "R"
        case .neutral: "N"
        case .drive: "D"
        }
    }

    private static func profileName(_ config: ConfigSummary) -> String {
        switch config.profile {
        case .factory: "Factory"
        case .preset(let name): name
        case .custom: "Custom"
        }
    }
}
