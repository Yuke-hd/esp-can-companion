import Foundation

/// Acceleration in g on the vehicle's two horizontal axes.
///
/// Positive `longitudinal` is forward acceleration (negative is braking) and
/// positive `lateral` is acceleration toward the right (a right turn), as the
/// controller reports them. The axes and signs are reference candidates, not
/// vehicle-validated; `GMeterModel.Configuration.dotDirection` is the one place
/// to flip the on-screen direction if they turn out inverted.
public struct GForce: Equatable, Sendable {
    /// Standard gravity, used to convert m/s² to g. The firmware never converts.
    public static let standardGravity = 9.80665

    public var longitudinal: Double
    public var lateral: Double

    public init(longitudinal: Double, lateral: Double) {
        self.longitudinal = longitudinal
        self.lateral = lateral
    }

    /// Converts readings in m/s² to g.
    public init(longitudinalMetersPerSecondSquared longitudinal: Double, lateralMetersPerSecondSquared lateral: Double) {
        self.init(longitudinal: longitudinal / Self.standardGravity, lateral: lateral / Self.standardGravity)
    }

    /// Total horizontal acceleration in g.
    public var magnitude: Double { hypot(longitudinal, lateral) }
}

/// Turns acceleration samples into what the Drive g-meter may show: a smoothed
/// dot, decaying per-direction peaks and a short trail.
///
/// A pure value type with no clock of its own: every update carries the
/// instant it happened at, so behaviour depends only on the samples and
/// instants supplied. A nil sample (any axis not live, layout 1, or a stalled
/// stream) clears everything; nothing is interpolated across the gap.
///
/// Presentation values (`dot`, `trail`, `peaks`, `peakPosition(_:)`) are in g
/// on screen axes, x to the right and y up, and clamp to the ring at
/// `Configuration.ringRange` without rescaling. `smoothed` keeps the
/// unclamped value for numeric text.
public struct GMeterModel: Equatable, Sendable {
    /// Which way the dot moves for a given acceleration.
    public enum DotDirection: Equatable, Sendable {
        /// Toward the force felt by occupants: braking moves the dot up,
        /// accelerating down, a right turn left.
        case feltForce
        /// Along the vehicle's acceleration: the mirror of `feltForce`.
        case acceleration
    }

    /// Every tuning constant of the g-meter, in one place.
    public struct Configuration: Equatable, Sendable {
        /// Exponential smoothing time constant.
        public var smoothingTimeConstant: Duration
        /// How long a peak is held at its value before it starts to decay.
        public var peakHold: Duration
        /// How long a held peak takes to decay linearly to zero.
        public var peakDecay: Duration
        /// How far back the trail reaches.
        public var trailWindow: Duration
        /// The most trail points kept, newest included. Zero or less keeps no
        /// trail; the initialiser clamps negative values to zero.
        public var trailCapacity: Int
        /// The ring's radius in g; presentation values clamp to it.
        public var ringRange: Double
        /// The dot-direction convention; flip here if the real axes are inverted.
        public var dotDirection: DotDirection

        public init(
            smoothingTimeConstant: Duration,
            peakHold: Duration,
            peakDecay: Duration,
            trailWindow: Duration,
            trailCapacity: Int,
            ringRange: Double,
            dotDirection: DotDirection
        ) {
            self.smoothingTimeConstant = smoothingTimeConstant
            self.peakHold = peakHold
            self.peakDecay = peakDecay
            self.trailWindow = trailWindow
            self.trailCapacity = max(0, trailCapacity)
            self.ringRange = ringRange
            self.dotDirection = dotDirection
        }

        /// The defaults agreed in the g-meter spec.
        public static let standard = Configuration(
            smoothingTimeConstant: .milliseconds(150),
            peakHold: .seconds(2),
            peakDecay: .seconds(2),
            trailWindow: .milliseconds(750),
            trailCapacity: 12,
            ringRange: 1.0,
            dotDirection: .feltForce
        )
    }

    /// A position on the g-meter face in g: x to the right, y up.
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// One trail point, newest last. `age` is measured from the latest update.
    public struct TrailPoint: Equatable, Sendable {
        public var position: Point
        public var age: Duration

        public init(position: Point, age: Duration) {
            self.position = position
            self.age = age
        }
    }

    /// The direction of the vehicle's acceleration a peak belongs to, not where
    /// its marker sits on the face: `right` is a right turn and `brake` is
    /// braking. With the default `.feltForce` dot direction the `right` marker
    /// is drawn on the left of the face and the `brake` marker at the top; use
    /// `peakPosition(_:)` for the on-screen position.
    public enum PeakDirection: CaseIterable, Equatable, Sendable {
        case accel, brake, left, right
    }

    /// Recent maximum magnitudes in g per direction, each non-negative and
    /// clamped to the ring.
    ///
    /// Peaks follow the smoothed value, not raw samples, so a brief spike is
    /// recorded at its smoothed height. The held peaks are stored unclamped
    /// and clamped only here, in presentation: a peak above the ring decays
    /// from its real value, so its marker dwells on the rim until the decay
    /// brings it inside the ring.
    public struct Peaks: Equatable, Sendable {
        public var accel: Double
        public var brake: Double
        public var left: Double
        public var right: Double

        public static let zero = Peaks(accel: 0, brake: 0, left: 0, right: 0)

        public subscript(direction: PeakDirection) -> Double {
            get {
                switch direction {
                case .accel: accel
                case .brake: brake
                case .left: left
                case .right: right
                }
            }
            set {
                switch direction {
                case .accel: accel = newValue
                case .brake: brake = newValue
                case .left: left = newValue
                case .right: right = newValue
                }
            }
        }
    }

    private struct HeldPeak: Equatable, Sendable {
        var value: Double
        var setAt: ContinuousClock.Instant
    }

    public let configuration: Configuration
    /// The smoothed acceleration, unclamped; nil when there is no live data.
    public private(set) var smoothed: GForce?
    public private(set) var peaks: Peaks = .zero
    private var lastUpdate: ContinuousClock.Instant?
    private var heldPeaks: [PeakDirection: HeldPeak] = [:]
    private var trailSamples: [TrailSample] = []

    private struct TrailSample: Equatable, Sendable {
        var position: Point
        var at: ContinuousClock.Instant
    }

    public init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    /// The dot, clamped to the ring; nil when there is no live data.
    public var dot: Point? { smoothed.map(position) }

    /// The trail, oldest first; the newest point is the current dot.
    public var trail: [TrailPoint] {
        guard let lastUpdate else { return [] }
        return trailSamples.map { TrailPoint(position: $0.position, age: lastUpdate - $0.at) }
    }

    /// Where `direction`'s peak marker sits on the face.
    public func peakPosition(_ direction: PeakDirection) -> Point {
        let magnitude = peaks[direction]
        let force = switch direction {
        case .accel: GForce(longitudinal: magnitude, lateral: 0)
        case .brake: GForce(longitudinal: -magnitude, lateral: 0)
        case .left: GForce(longitudinal: 0, lateral: -magnitude)
        case .right: GForce(longitudinal: 0, lateral: magnitude)
        }
        return position(of: force)
    }

    /// Feeds one sample taken at `now`. A nil sample clears the dot, trail and
    /// peaks. A sample at or before the previous instant is ignored.
    public mutating func update(_ acceleration: GForce?, at now: ContinuousClock.Instant) {
        guard let acceleration else {
            self = GMeterModel(configuration: configuration)
            return
        }
        if let lastUpdate, now <= lastUpdate { return }

        let next: GForce
        if let previous = smoothed, let lastUpdate {
            let alpha = 1 - exp(-Self.seconds(now - lastUpdate) / Self.seconds(configuration.smoothingTimeConstant))
            next = GForce(
                longitudinal: previous.longitudinal + alpha * (acceleration.longitudinal - previous.longitudinal),
                lateral: previous.lateral + alpha * (acceleration.lateral - previous.lateral)
            )
        } else {
            next = acceleration
        }
        smoothed = next
        lastUpdate = now

        updatePeaks(with: next, at: now)
        let window = configuration.trailWindow
        trailSamples.append(TrailSample(position: position(of: next), at: now))
        trailSamples.removeAll { now - $0.at > window }
        // Clamped again here because `trailCapacity` is a mutable property.
        let capacity = max(0, configuration.trailCapacity)
        if trailSamples.count > capacity {
            trailSamples.removeFirst(trailSamples.count - capacity)
        }
    }

    // MARK: Internals

    private mutating func updatePeaks(with force: GForce, at now: ContinuousClock.Instant) {
        let magnitudes: [PeakDirection: Double] = [
            .accel: max(force.longitudinal, 0),
            .brake: max(-force.longitudinal, 0),
            .left: max(-force.lateral, 0),
            .right: max(force.lateral, 0),
        ]
        var current = Peaks.zero
        for direction in PeakDirection.allCases {
            let decayed = heldPeaks[direction].map { decayedValue(of: $0, at: now) } ?? 0
            let magnitude = magnitudes[direction] ?? 0
            let value: Double
            if magnitude > 0, magnitude >= decayed {
                heldPeaks[direction] = HeldPeak(value: magnitude, setAt: now)
                value = magnitude
            } else {
                value = decayed
            }
            current[direction] = min(value, configuration.ringRange)
        }
        peaks = current
    }

    private func decayedValue(of peak: HeldPeak, at now: ContinuousClock.Instant) -> Double {
        let sinceHoldEnded = Self.seconds(now - peak.setAt) - Self.seconds(configuration.peakHold)
        guard sinceHoldEnded > 0 else { return peak.value }
        let decay = Self.seconds(configuration.peakDecay)
        guard decay > 0 else { return 0 }
        return peak.value * max(0, 1 - sinceHoldEnded / decay)
    }

    /// Maps a force to the face using the dot direction, clamped radially to the ring.
    private func position(of force: GForce) -> Point {
        let sign: Double = configuration.dotDirection == .feltForce ? -1 : 1
        var point = Point(x: sign * force.lateral, y: sign * force.longitudinal)
        let radius = hypot(point.x, point.y)
        if radius > configuration.ringRange {
            let scale = configuration.ringRange / radius
            point = Point(x: point.x * scale, y: point.y * scale)
        }
        return point
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
