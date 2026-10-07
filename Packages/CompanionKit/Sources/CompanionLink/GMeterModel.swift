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
/// on screen axes, x to the right and y up, and clamp to the active
/// `ringRange` without rescaling. Peaks and trail are stored unclamped, so
/// they keep their g values when the range changes. `smoothed` keeps the
/// unclamped value for numeric text.
///
/// The ring auto-ranges: it starts at `Configuration.compactRange`, expands
/// to `expandedRange` as soon as the smoothed magnitude or a held peak goes
/// beyond the compact ring, and shrinks back only once both have stayed at or
/// below `shrinkThreshold` for `rangeSettle`.
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
        /// The ring's radius in g at start, with no data and in everyday driving.
        public var compactRange: Double
        /// The ring's radius in g once the magnitude exceeds `compactRange`.
        /// Presentation values clamp to the active range.
        public var expandedRange: Double
        /// The magnitude in g the smoothed value and every held peak must stay
        /// at or below before the range shrinks. Keeping it under
        /// `compactRange` leaves a hysteresis band, so the scale does not
        /// flicker around the compact ring.
        public var shrinkThreshold: Double
        /// How long the magnitude must stay at or below `shrinkThreshold`
        /// before the range shrinks back to `compactRange`.
        public var rangeSettle: Duration
        /// The dot-direction convention; flip here if the real axes are inverted.
        public var dotDirection: DotDirection

        public init(
            smoothingTimeConstant: Duration,
            peakHold: Duration,
            peakDecay: Duration,
            trailWindow: Duration,
            trailCapacity: Int,
            compactRange: Double,
            expandedRange: Double,
            shrinkThreshold: Double,
            rangeSettle: Duration,
            dotDirection: DotDirection
        ) {
            self.smoothingTimeConstant = smoothingTimeConstant
            self.peakHold = peakHold
            self.peakDecay = peakDecay
            self.trailWindow = trailWindow
            self.trailCapacity = max(0, trailCapacity)
            self.compactRange = compactRange
            self.expandedRange = expandedRange
            self.shrinkThreshold = shrinkThreshold
            self.rangeSettle = rangeSettle
            self.dotDirection = dotDirection
        }

        /// The defaults agreed in the g-meter spec.
        public static let standard = Configuration(
            smoothingTimeConstant: .milliseconds(150),
            peakHold: .seconds(2),
            peakDecay: .seconds(2),
            trailWindow: .milliseconds(750),
            trailCapacity: 12,
            compactRange: 0.5,
            expandedRange: 1.0,
            shrinkThreshold: 0.45,
            rangeSettle: .seconds(3),
            dotDirection: .feltForce
        )

        /// A dashed ring inside the rim: `value` in g and how visible it is.
        public struct RingMark: Equatable, Sendable {
            public var value: Double
            public var opacity: Double

            public init(value: Double, opacity: Double) {
                self.value = value
                self.opacity = opacity
            }
        }

        /// The dashed rings to draw inside a rim of radius `range` g: half of
        /// each range, the compact one fully visible at `compactRange` and the
        /// expanded one at `expandedRange`, cross-fading while the drawn range
        /// animates between them.
        public func innerMarks(atRange range: Double) -> [RingMark] {
            let span = expandedRange - compactRange
            let progress = span > 0 ? min(max((range - compactRange) / span, 0), 1) : 1
            return [
                RingMark(value: compactRange / 2, opacity: 1 - progress),
                RingMark(value: expandedRange / 2, opacity: progress),
            ]
        }
    }

    /// A position on the g-meter face in g: x to the right, y up.
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        /// This point moved radially onto a circle of `radius` g if it lies
        /// beyond it; unchanged otherwise.
        public func clamped(toRadius radius: Double) -> Point {
            let distance = hypot(x, y)
            guard distance > radius, distance > 0 else { return self }
            let scale = radius / distance
            return Point(x: x * scale, y: y * scale)
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
    /// clamped to the active ring.
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
    /// The active ring radius in g: `compactRange` or `expandedRange`.
    public private(set) var ringRange: Double
    private var lastUpdate: ContinuousClock.Instant?
    private var heldPeaks: [PeakDirection: HeldPeak] = [:]
    private var trailSamples: [TrailSample] = []
    /// When the magnitude last fell to or below `shrinkThreshold` while
    /// expanded; nil while it is above, or when compact.
    private var settlingSince: ContinuousClock.Instant?

    private struct TrailSample: Equatable, Sendable {
        /// Unclamped, so the point keeps its g value across a range change.
        var position: Point
        var at: ContinuousClock.Instant
    }

    public init(configuration: Configuration = .standard) {
        self.configuration = configuration
        ringRange = configuration.compactRange
    }

    /// The dot, clamped to the ring; nil when there is no live data.
    public var dot: Point? { smoothed.map { position(of: $0).clamped(toRadius: ringRange) } }

    /// The trail, oldest first; the newest point is the current dot.
    public var trail: [TrailPoint] {
        guard let lastUpdate else { return [] }
        return trailSamples.map {
            TrailPoint(position: $0.position.clamped(toRadius: ringRange), age: lastUpdate - $0.at)
        }
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
        // `peaks` is already clamped to the ring, and each lies on one axis.
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

        let heldPeak = updateHeldPeaks(with: next, at: now)
        updateRange(demand: max(next.magnitude, heldPeak), at: now)
        peaks = Peaks(
            accel: min(peaks.accel, ringRange),
            brake: min(peaks.brake, ringRange),
            left: min(peaks.left, ringRange),
            right: min(peaks.right, ringRange)
        )
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

    /// Updates the held peaks and sets `peaks` to them unclamped; returns the
    /// largest. The caller clamps `peaks` once the range is known.
    private mutating func updateHeldPeaks(with force: GForce, at now: ContinuousClock.Instant) -> Double {
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
            current[direction] = value
        }
        peaks = current
        return PeakDirection.allCases.map { current[$0] }.max() ?? 0
    }

    /// Expands at once when `demand` exceeds the compact ring; shrinks only
    /// after it has stayed at or below the shrink threshold for the settle period.
    private mutating func updateRange(demand: Double, at now: ContinuousClock.Instant) {
        if demand > configuration.compactRange {
            ringRange = configuration.expandedRange
            settlingSince = nil
        } else if ringRange != configuration.compactRange {
            guard demand <= configuration.shrinkThreshold else {
                settlingSince = nil
                return
            }
            let since = settlingSince ?? now
            if now - since >= configuration.rangeSettle {
                ringRange = configuration.compactRange
                settlingSince = nil
            } else {
                settlingSince = since
            }
        }
    }

    private func decayedValue(of peak: HeldPeak, at now: ContinuousClock.Instant) -> Double {
        let sinceHoldEnded = Self.seconds(now - peak.setAt) - Self.seconds(configuration.peakHold)
        guard sinceHoldEnded > 0 else { return peak.value }
        let decay = Self.seconds(configuration.peakDecay)
        guard decay > 0 else { return 0 }
        return peak.value * max(0, 1 - sinceHoldEnded / decay)
    }

    /// Maps a force to the face using the dot direction, unclamped.
    private func position(of force: GForce) -> Point {
        let sign: Double = configuration.dotDirection == .feltForce ? -1 : 1
        return Point(x: sign * force.lateral, y: sign * force.longitudinal)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
