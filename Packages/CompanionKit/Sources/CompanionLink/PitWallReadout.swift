import Foundation
import CompanionProtocol

/// What the Pit Wall shows for one live signal frame: the words, the tone of
/// each value and its freshness, kept apart from SwiftUI so tests cover them.
///
/// Values follow the live-signals rules: only `Fresh` reads as fresh, an
/// unverified value is shown and labelled, and a stale, unknown or missing
/// value is not shown at all. A stalled stream arrives here as
/// `LiveSignalFrame.unknown`, so it shows every signal as unknown.
public struct PitWallReadout: Equatable, Sendable {
    /// How a signal's freshness is labelled.
    public enum Freshness: Equatable, Sendable {
        case fresh, unverified, stale, noData, unavailable, failed, unsupported, unknown

        init(_ availability: SignalAvailability) {
            switch availability {
            case .fresh: self = .fresh
            case .freshnessUnverified: self = .unverified
            case .stale: self = .stale
            case .noData: self = .noData
            case .unavailable: self = .unavailable
            case .readFailed: self = .failed
            case .notSupported: self = .unsupported
            case .unknown: self = .unknown
            }
        }

        public var title: String {
            switch self {
            case .fresh: "Fresh"
            case .unverified: "Unverified"
            case .stale: "Stale"
            case .noData: "No data"
            case .unavailable: "Unavailable"
            case .failed: "Read failed"
            case .unsupported: "Not supported"
            case .unknown: "Unknown"
            }
        }

        /// True when a value with this freshness may be shown.
        public var showsValue: Bool { self == .fresh || self == .unverified }

        /// Higher is worse, to combine several signals into one tile.
        var rank: Int {
            switch self {
            case .fresh: 0
            case .unverified: 1
            case .stale: 2
            case .noData: 3
            case .unavailable: 4
            case .unsupported: 5
            case .failed: 6
            case .unknown: 7
            }
        }
    }

    /// The color role of a tile value; the view maps it to a theme color.
    public enum Tone: Equatable, Sendable {
        /// Plain white, such as "RELEASED" or "LOCKED".
        case normal
        /// Something is on that the driver should see: a turn signal or the brake.
        case active
        /// A good resting state, such as doors closed.
        case calm
        /// Off or idle.
        case muted
    }

    public struct Tile: Equatable, Sendable, Identifiable {
        public var title: String
        /// The value in words, or nil when it must not be shown.
        public var value: String?
        public var tone: Tone
        public var freshness: Freshness

        public var id: String { title }

        /// One VoiceOver label for the tile.
        public var accessibilityText: String {
            "\(title), \(value ?? "no value"), \(freshness.title)"
        }
    }

    /// Number of dots in the shift light row.
    public static let shiftLightCount = 15
    /// RPM scale when the config has no RPM rules.
    public static let defaultRPMScale: Double = 7000

    public var rpm: Double?
    public var rpmFreshness: Freshness
    /// "4" for fourth gear, "R" for reverse, nil when not shown.
    public var gear: String?
    public var gearFreshness: Freshness
    public var speedKPH: Int?
    public var speedFreshness: Freshness
    /// How many shift lights are lit, `0...shiftLightCount`.
    public var litShiftLights: Int
    /// Index of the first shift light at or above the redline, nil without one.
    public var firstRedShiftLight: Int?
    /// RPM bar fill and the redline marker, both `0...1`.
    public var rpmFraction: Double
    public var redlineFraction: Double?
    /// Nil until a frame says whether the telemetry facade started.
    public var isTelemetryStarted: Bool?
    public var tiles: [Tile]

    public init(frame: LiveSignalFrame, band: ConfigSummary.RPMBand? = nil) {
        rpmFreshness = Freshness(frame.engineRPM.availability)
        rpm = rpmFreshness.showsValue ? frame.engineRPM.value : nil

        gearFreshness = Freshness(frame.actualGear.availability)
        gear = gearFreshness.showsValue ? frame.actualGear.value.map(Self.gearText) : nil

        speedFreshness = Freshness(frame.speedKPH.availability)
        speedKPH = speedFreshness.showsValue ? frame.speedKPH.value.map { Int($0.rounded()) } : nil

        // A config may use any finite threshold, however large, so all of
        // this stays in floating point and only bounded values become Int.
        let scale = Self.scale(band)
        let low = band?.fill?.from ?? 0
        // Without a fill range, light up to the bar's scale, so a redline
        // still falls inside the row and its lights turn red.
        let high = max(band?.fill?.to ?? scale, low + 1)
        let span = high - low
        let lights = Double(Self.shiftLightCount)
        /// Where `value` falls along the row, in lights; nil when the row
        /// cannot place it.
        func position(_ value: Double) -> Double? {
            let position = (value - low) / span * lights
            return position.isFinite ? position : nil
        }
        if let rpm {
            litShiftLights = position(rpm).map { Int(min(max($0, 0), lights).rounded()) } ?? 0
            rpmFraction = Self.fraction(rpm / scale)
        } else {
            litShiftLights = 0
            rpmFraction = 0
        }
        if let redline = band?.redline {
            // A light is red when the top of its span passes the redline.
            if let red = position(redline)?.rounded(.down), red < lights {
                firstRedShiftLight = Int(max(red, 0))
            } else {
                firstRedShiftLight = nil
            }
            redlineFraction = Self.fraction(redline / scale)
        } else {
            firstRedShiftLight = nil
            redlineFraction = nil
        }

        isTelemetryStarted = frame == .unknown ? nil : frame.isTelemetryStarted
        tiles = Self.tiles(frame)
    }

    /// The RPM bar's full scale: a little past the highest RPM the config uses.
    static func scale(_ band: ConfigSummary.RPMBand?) -> Double {
        let top = max(band?.fill?.to ?? 0, band?.redline ?? 0)
        guard top > 0, top.isFinite else { return defaultRPMScale }
        let scale = (top * 1.08 / 500).rounded(.up) * 500
        return scale.isFinite ? scale : top
    }

    /// `value` clamped to `0...1`, or 0 when it is not a number.
    static func fraction(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : (value > 0 ? 1 : 0)
    }

    /// A reported gear. `unknown` is a value the vehicle sent, not a missing
    /// one, so it shows as "?".
    static func gearText(_ gear: WireValue<ActualGear>) -> String {
        guard case .known(let gear) = gear else { return "?" }
        switch gear {
        case .unknown: return "?"
        case .shifting: return "Shift"
        case .parkOrNeutral: return "P/N"
        case .park: return "P"
        case .neutral: return "N"
        case .reverse: return "R"
        case .first: return "1"
        case .second: return "2"
        case .third: return "3"
        case .fourth: return "4"
        case .fifth: return "5"
        case .sixth: return "6"
        }
    }

    // MARK: Tiles

    static func tiles(_ frame: LiveSignalFrame) -> [Tile] {
        [
            tile("Brake", frame.brakePressed) { $0 ? ("Pressed", .active) : ("Released", .normal) },
            tile("Turn", frame.turnState) { turn in
                switch turn {
                case .known(.left): ("Left", .active)
                case .known(.right): ("Right", .active)
                case .known(.hazard): ("Both", .active)
                case .known(.off): ("Off", .muted)
                default: nil
                }
            },
            tile("Hazard", frame.hazardRequest) { $0 ? ("On", .active) : ("Off", .muted) },
            doors(frame),
            tile("Lock", frame.doorsUnlocked) { $0 ? ("Unlocked", .active) : ("Locked", .normal) },
            tile("Wipers", frame.frontWiperPosition) { wiper in
                switch wiper {
                case .known(.off): ("Off", .muted)
                case .known(.on): ("On", .normal)
                case .known(.high): ("High", .normal)
                case .known(.intermittent): ("Int", .normal)
                default: nil
                }
            },
        ]
    }

    /// `describe` returns nil for a reported `unknown` choice or a code this
    /// app does not know; that is still a value, so it shows as "Unknown".
    static func tile<V>(_ title: String, _ reading: SignalReading<V>, _ describe: (V) -> (String, Tone)?) -> Tile {
        let freshness = Freshness(reading.availability)
        guard freshness.showsValue, let value = reading.value else {
            return Tile(title: title, value: nil, tone: .muted, freshness: freshness)
        }
        guard let (text, tone) = describe(value) else {
            return Tile(title: title, value: "Unknown", tone: .muted, freshness: freshness)
        }
        return Tile(title: title, value: text, tone: tone, freshness: freshness)
    }

    /// All four doors and the liftgate: open when any of them is, closed only
    /// when every one shows closed, and as fresh as the least fresh.
    static func doors(_ frame: LiveSignalFrame) -> Tile {
        let readings = [frame.doorFrontLeftRHD, frame.doorFrontRightRHD, frame.doorRearLeft, frame.doorRearRight, frame.liftgateOpen]
        let shown = readings.filter { Freshness($0.availability).showsValue && $0.value != nil }
        if let open = shown.first(where: { $0.value == true }) {
            return Tile(title: "Doors", value: "Open", tone: .active, freshness: Freshness(open.availability))
        }
        let freshness = readings.map { Freshness($0.availability) }.max { $0.rank < $1.rank } ?? .unknown
        guard shown.count == readings.count else {
            return Tile(title: "Doors", value: nil, tone: .muted, freshness: freshness)
        }
        return Tile(title: "Doors", value: "Closed", tone: .calm, freshness: freshness)
    }
}
