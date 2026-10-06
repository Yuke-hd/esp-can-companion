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
    public let selector: String?
    public let selectorFreshness: PitWallReadout.Freshness
    public let redlineState: RedlineState
    public let status: Status
    /// Layout v1 has no throttle, brake pressure or boost signals. These
    /// tiles are explicit placeholders rather than fabricated zero values.
    public let throttle: PitWallReadout.Tile
    public let brakePressure: PitWallReadout.Tile
    public let boost: PitWallReadout.Tile
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
        linkState: LinkState = .unknown,
        framesPerSecond: Int = 0
    ) {
        let band = activeConfig?.rpmBand
        let pitWall = PitWallReadout(frame: frame, band: band)
        self.pitWall = pitWall

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
        throttle = Self.placeholder(title: "Throttle", freshness: unsupported)
        brakePressure = Self.placeholder(title: "Brake pressure", freshness: unsupported)
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

    /// Explicitly unavailable values for the signals absent in layout v1.
    public var throttlePercent: Double? { nil }
    public var throttleFreshness: PitWallReadout.Freshness { throttle.freshness }
    public var brakePressurePercent: Double? { nil }
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
