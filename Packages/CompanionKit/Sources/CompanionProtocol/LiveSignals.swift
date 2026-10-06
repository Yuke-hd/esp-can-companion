import Foundation

/// How current a live-signal reading is. Copied from the controller; never
/// derived from frame timing.
public enum SignalAvailability: Equatable, Sendable {
    /// The provider has no observation yet.
    case noData
    /// Fresh within the signal's verified freshness timeout. The only fresh state.
    case fresh
    /// Older than its freshness timeout.
    case stale
    /// Valid, but the signal has no freshness timeout configured.
    case freshnessUnverified
    /// The provider reports the reading unavailable.
    case unavailable
    /// The controller's read failed.
    case readFailed
    /// The controller's build cannot read this signal.
    case notSupported
    /// Not known: a reserved code, a code the spec forbids for this signal,
    /// a stalled stream, or no frame yet.
    case unknown

    init(code: UInt8) {
        switch code & 0x07 {
        case 0: self = .noData
        case 1: self = .fresh
        case 2: self = .stale
        case 3: self = .freshnessUnverified
        case 4: self = .unavailable
        case 5: self = .readFailed
        case 6: self = .notSupported
        default: self = .unknown
        }
    }

    public var isFresh: Bool { self == .fresh }
}

/// One signal's reading. `value` is nil when the frame carried no value; a
/// value with a non-fresh availability may be shown only as not fresh.
public struct SignalReading<Value: Equatable & Sendable>: Equatable, Sendable {
    public var availability: SignalAvailability
    public var value: Value?

    public init(availability: SignalAvailability, value: Value?) {
        self.availability = availability
        self.value = value
    }

    public static var unknown: SignalReading { SignalReading(availability: .unknown, value: nil) }

    /// True only for a fresh reading that carries a value.
    public var isLive: Bool { availability.isFresh && value != nil }
}

// MARK: - Choice codes (live-signals.md, "Enum choice codes")

public enum TurnState: UInt8, Equatable, Sendable {
    case unknown = 0, off, left, right, hazard
}

public enum SelectorPosition: UInt8, Equatable, Sendable {
    case unknown = 0, shifting, park, reverse, neutral, drive
}

public enum ActualGear: UInt8, Equatable, Sendable {
    case unknown = 0, parkOrNeutral, park, neutral, reverse, first, second, third, fourth, fifth, sixth, shifting
}

public enum FrontWiperPosition: UInt8, Equatable, Sendable {
    case unknown = 0, off, on, high, intermittent
}

/// One Live signals notification, decoded. Layout version 1 (23 bytes) or 2
/// (28 bytes, adding acceleration).
public struct LiveSignalFrame: Equatable, Sendable {
    /// Layout 1, the original frame, and what `init(decoding:)` decodes.
    public static let layoutVersion: UInt8 = 1
    public static let length = 23
    /// Layout 2 appends longitudinal and lateral acceleration.
    public static let layout2Version: UInt8 = 2
    public static let layout2Length = 28

    /// Each decodable layout version with its exact frame length.
    static let lengths: [UInt8: Int] = [layoutVersion: length, layout2Version: layout2Length]

    /// Wrapping frame counter; restarts at 0 on each connection.
    public var sequence: UInt8
    /// The telemetry facade started during this boot.
    public var isTelemetryStarted: Bool

    public var engineRPM: SignalReading<Double>
    public var speedKPH: SignalReading<Double>
    public var turnState: SignalReading<WireValue<TurnState>>
    public var selectorPosition: SignalReading<WireValue<SelectorPosition>>
    public var actualGear: SignalReading<WireValue<ActualGear>>
    public var frontWiperPosition: SignalReading<WireValue<FrontWiperPosition>>
    public var hazardRequest: SignalReading<Bool>
    public var turnRequestLeft: SignalReading<Bool>
    public var turnRequestRight: SignalReading<Bool>
    public var indicatorLampLeft: SignalReading<Bool>
    public var indicatorLampRight: SignalReading<Bool>
    public var liftgateOpen: SignalReading<Bool>
    public var doorRearRight: SignalReading<Bool>
    public var doorRearLeft: SignalReading<Bool>
    public var doorFrontLeftRHD: SignalReading<Bool>
    public var doorFrontRightRHD: SignalReading<Bool>
    public var doorsUnlocked: SignalReading<Bool>
    public var wiperLow: SignalReading<Bool>
    /// Never fresh: the protocol defines no brake timeout. A frame that claims
    /// otherwise is reported as `unknown`.
    public var brakePressed: SignalReading<Bool>
    /// Longitudinal acceleration in m/s²; `.unknown` in layout 1 frames.
    public var longitudinalAcceleration: SignalReading<Double>
    /// Lateral acceleration in m/s²; `.unknown` in layout 1 frames.
    public var lateralAcceleration: SignalReading<Double>

    /// Every signal unknown with no values: what the app shows before the
    /// first frame and while the stream is stalled.
    public static let unknown = LiveSignalFrame(
        sequence: 0,
        isTelemetryStarted: false,
        engineRPM: .unknown, speedKPH: .unknown, turnState: .unknown,
        selectorPosition: .unknown, actualGear: .unknown, frontWiperPosition: .unknown,
        hazardRequest: .unknown, turnRequestLeft: .unknown, turnRequestRight: .unknown,
        indicatorLampLeft: .unknown, indicatorLampRight: .unknown, liftgateOpen: .unknown,
        doorRearRight: .unknown, doorRearLeft: .unknown, doorFrontLeftRHD: .unknown,
        doorFrontRightRHD: .unknown, doorsUnlocked: .unknown, wiperLow: .unknown,
        brakePressed: .unknown,
        longitudinalAcceleration: .unknown, lateralAcceleration: .unknown
    )

    init(
        sequence: UInt8,
        isTelemetryStarted: Bool,
        engineRPM: SignalReading<Double>,
        speedKPH: SignalReading<Double>,
        turnState: SignalReading<WireValue<TurnState>>,
        selectorPosition: SignalReading<WireValue<SelectorPosition>>,
        actualGear: SignalReading<WireValue<ActualGear>>,
        frontWiperPosition: SignalReading<WireValue<FrontWiperPosition>>,
        hazardRequest: SignalReading<Bool>,
        turnRequestLeft: SignalReading<Bool>,
        turnRequestRight: SignalReading<Bool>,
        indicatorLampLeft: SignalReading<Bool>,
        indicatorLampRight: SignalReading<Bool>,
        liftgateOpen: SignalReading<Bool>,
        doorRearRight: SignalReading<Bool>,
        doorRearLeft: SignalReading<Bool>,
        doorFrontLeftRHD: SignalReading<Bool>,
        doorFrontRightRHD: SignalReading<Bool>,
        doorsUnlocked: SignalReading<Bool>,
        wiperLow: SignalReading<Bool>,
        brakePressed: SignalReading<Bool>,
        longitudinalAcceleration: SignalReading<Double>,
        lateralAcceleration: SignalReading<Double>
    ) {
        self.sequence = sequence
        self.isTelemetryStarted = isTelemetryStarted
        self.engineRPM = engineRPM
        self.speedKPH = speedKPH
        self.turnState = turnState
        self.selectorPosition = selectorPosition
        self.actualGear = actualGear
        self.frontWiperPosition = frontWiperPosition
        self.hazardRequest = hazardRequest
        self.turnRequestLeft = turnRequestLeft
        self.turnRequestRight = turnRequestRight
        self.indicatorLampLeft = indicatorLampLeft
        self.indicatorLampRight = indicatorLampRight
        self.liftgateOpen = liftgateOpen
        self.doorRearRight = doorRearRight
        self.doorRearLeft = doorRearLeft
        self.doorFrontLeftRHD = doorFrontLeftRHD
        self.doorFrontRightRHD = doorFrontRightRHD
        self.doorsUnlocked = doorsUnlocked
        self.wiperLow = wiperLow
        self.brakePressed = brakePressed
        self.longitudinalAcceleration = longitudinalAcceleration
        self.lateralAcceleration = lateralAcceleration
    }

    /// Decodes a layout version 1 frame. A frame of another layout or length is rejected.
    public init(decoding value: Data) throws {
        try self.init(decoding: value, layoutVersion: Self.layoutVersion)
    }

    /// Decodes a frame of exactly `layoutVersion`, the version the controller
    /// reported in Device info. The frame's own version byte and its length
    /// must both match, so a layout 2 frame never decodes as layout 1 or back.
    public init(decoding value: Data, layoutVersion: UInt8) throws {
        guard let length = Self.lengths[layoutVersion] else {
            throw ProtocolDecodingError.invalidValue(field: "layout_version")
        }
        var reader = ByteReader(value)
        guard try reader.u8("layout_version") == layoutVersion else {
            throw ProtocolDecodingError.invalidValue(field: "layout_version")
        }
        guard value.count == length else {
            throw value.count < length
                ? ProtocolDecodingError.truncated(field: "frame")
                : ProtocolDecodingError.invalidValue(field: "frame")
        }
        sequence = try reader.u8("sequence")
        isTelemetryStarted = try reader.u8("flags") & 0x01 != 0
        let rpmRaw = try reader.u16("engine_rpm")
        let speedRaw = try reader.u16("speed_kph")
        let turnRaw = try reader.u8("turn_state")
        let selectorRaw = try reader.u8("selector_position")
        let gearRaw = try reader.u8("actual_gear")
        let wiperRaw = try reader.u8("front_wiper_position")
        let booleans = try reader.u16("booleans")
        // One nibble per signal: 19 in layout 1, 21 in layout 2.
        let status = Array(try reader.bytes(layoutVersion == Self.layout2Version ? 11 : 10, "status"))

        /// Signal `index`'s status nibble: low nibble for even, high for odd.
        func nibble(_ index: Int) -> (availability: SignalAvailability, hasValue: Bool) {
            let byte = status[index / 2]
            let bits = index % 2 == 0 ? byte & 0x0F : byte >> 4
            return (SignalAvailability(code: bits & 0x07), bits & 0x08 != 0)
        }
        func reading<V>(_ index: Int, _ value: V) -> SignalReading<V> {
            let (availability, hasValue) = nibble(index)
            return SignalReading(availability: availability, value: hasValue ? value : nil)
        }
        func flag(_ index: Int, bit: Int) -> SignalReading<Bool> {
            reading(index, booleans & (1 << bit) != 0)
        }

        engineRPM = reading(0, Double(rpmRaw) / 4)
        speedKPH = reading(1, Double(speedRaw) / 100)
        turnState = reading(2, WireValue(rawValue: turnRaw))
        selectorPosition = reading(3, WireValue(rawValue: selectorRaw))
        actualGear = reading(4, WireValue(rawValue: gearRaw))
        frontWiperPosition = reading(5, WireValue(rawValue: wiperRaw))
        hazardRequest = flag(6, bit: 0)
        turnRequestLeft = flag(7, bit: 1)
        turnRequestRight = flag(8, bit: 2)
        indicatorLampLeft = flag(9, bit: 3)
        indicatorLampRight = flag(10, bit: 4)
        liftgateOpen = flag(11, bit: 5)
        doorRearRight = flag(12, bit: 6)
        doorRearLeft = flag(13, bit: 7)
        doorFrontLeftRHD = flag(14, bit: 8)
        doorFrontRightRHD = flag(15, bit: 9)
        doorsUnlocked = flag(16, bit: 10)
        wiperLow = flag(17, bit: 11)
        brakePressed = flag(18, bit: 12)
        // Safety invariant 4: brake is never fresh. Keep the value, drop the claim.
        if brakePressed.availability == .fresh {
            brakePressed.availability = .unknown
        }

        if layoutVersion == Self.layout2Version {
            let longitudinalRaw = Int16(bitPattern: try reader.u16("acceleration_longitudinal"))
            let lateralRaw = Int16(bitPattern: try reader.u16("acceleration_lateral"))
            longitudinalAcceleration = reading(19, Double(longitudinalRaw) / 100)
            lateralAcceleration = reading(20, Double(lateralRaw) / 1000)
        } else {
            longitudinalAcceleration = .unknown
            lateralAcceleration = .unknown
        }
    }
}

/// Turns Live signals notifications into what the app may show, applying the
/// spec's stall rule: with no frame for `stallTimeout`, every signal is
/// unknown, not its last received availability.
///
/// A plain value type driven by the caller's clock, so it is easy to test.
public struct LiveSignalFeed: Sendable {
    public static let defaultStallTimeout: Duration = .seconds(2)

    public let stallTimeout: Duration
    /// The layout the controller reported in Device info; frames of any other layout are discarded.
    public let layoutVersion: UInt8
    private var latest: LiveSignalFrame?
    private var lastFrameAt: ContinuousClock.Instant?

    public init(
        stallTimeout: Duration = Self.defaultStallTimeout,
        layoutVersion: UInt8 = LiveSignalFrame.layoutVersion
    ) {
        self.stallTimeout = stallTimeout
        self.layoutVersion = layoutVersion
    }

    /// When the stream counts as stalled if no further frame arrives, or nil
    /// before the first frame.
    public var stallDeadline: ContinuousClock.Instant? {
        lastFrameAt.map { $0 + stallTimeout }
    }

    /// Records a notification. Returns the decoded frame, or nil when it was
    /// discarded (wrong layout or malformed). A discarded frame does not count
    /// as a sign of life.
    @discardableResult
    public mutating func receive(_ value: Data, at now: ContinuousClock.Instant) -> LiveSignalFrame? {
        guard let frame = try? LiveSignalFrame(decoding: value, layoutVersion: layoutVersion) else { return nil }
        latest = frame
        lastFrameAt = now
        return frame
    }

    /// True when no frame has arrived within `stallTimeout` (or none yet).
    public func isStalled(at now: ContinuousClock.Instant) -> Bool {
        guard let lastFrameAt else { return true }
        return now - lastFrameAt >= stallTimeout
    }

    /// What to show now: the latest frame, or all-unknown while stalled.
    public func snapshot(at now: ContinuousClock.Instant) -> LiveSignalFrame {
        guard let latest, !isStalled(at: now) else { return .unknown }
        return latest
    }
}
