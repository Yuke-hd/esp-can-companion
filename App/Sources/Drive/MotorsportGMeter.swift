import SwiftUI
import DesignSystem
import CompanionLink

/// A friction-circle g-meter for the Drive `auxiliary` slot: an auto-ranging
/// ring (±0.5 g with a 0.25 g mark, or ±1 g with a 0.5 g mark), a smoothed dot
/// with a short fading trail, decaying peak markers per direction and the
/// total g underneath. The active range is named beside the title; when it
/// changes, the label and rim briefly light up in the accent colour.
///
/// The view only displays: the readout decides liveness (both axes fresh) and
/// `GMeterModel` owns smoothing, peaks and the trail. A clock tick feeds the
/// model the current sample at an explicit instant, so the dot settles and the
/// peaks decay between frames as well as on them. A nil sample clears the
/// model; there is no dot and no zero while data is missing.
struct MotorsportGMeter: View {
    /// Same footprint the boost placeholder had, so the rest of Drive does not move.
    static let width: CGFloat = 128
    static let ringDiameter: CGFloat = 84
    /// How often the model is fed between frames, for smooth motion and decay.
    static let tick: Duration = .milliseconds(33)
    /// The ring's rescale when the range changes; instant under Reduce Motion.
    static let rangeAnimation: Animation = .easeInOut(duration: 0.35)
    /// The range-change highlight: a quick rise, then a slower fade.
    static let highlightRise: Animation = .easeOut(duration: 0.15)
    static let highlightFade: Animation = .easeIn(duration: 0.6)

    /// How the dial is drawn.
    enum Face {
        /// Crosshair, range marks and rim.
        case rings
        /// No crosshair or range marks: a triangle lattice, hidden in the
        /// dark, that a smaller dot lights around itself like a torch, and a
        /// rim broken by the held peak in each direction.
        case torch
    }

    let readout: DriveReadout
    var face: Face = .rings
    /// In the centre slot: the ring fills the space, its marks and dot growing
    /// with it, the title row is hidden and the total sits large behind the ring.
    var fillsSpace = false
    /// The total's size behind the centre ring, as a share of its diameter.
    private static let backdropValueShare: CGFloat = 0.3
    /// Dimmed so the dot, crosshair and peaks stay readable over it.
    private static let backdropValueOpacity = 0.45
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = GMeterModel()
    /// The latest sample, kept in state so the clock loop reads the current
    /// frame rather than the one captured when the task started.
    @State private var sample: GForce?
    /// 0…1: how strongly the range label and rim are lit after a range change.
    @State private var rangeHighlight = 0.0

    var body: some View {
        let live = readout.acceleration != nil && model.dot != nil
        VStack(spacing: Theme.Spacing.xxs) {
            if !fillsSpace { titleRow(live: live) }
            GMeterFace(model: model, range: model.ringRange, highlight: rangeHighlight, live: live, showsMotion: !reduceMotion, face: face)
                .aspectRatio(1, contentMode: .fit)
                .frame(
                    maxWidth: fillsSpace ? .infinity : Self.ringDiameter,
                    maxHeight: fillsSpace ? .infinity : Self.ringDiameter
                )
                .animation(reduceMotion ? nil : Self.rangeAnimation, value: model.ringRange)
                .background {
                    if fillsSpace {
                        GeometryReader { proxy in
                            valueRow(live: live, size: min(proxy.size.width, proxy.size.height) * Self.backdropValueShare)
                                .opacity(Self.backdropValueOpacity)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                }
            if !fillsSpace {
                valueRow(live: live, size: 20)
                    .fixedSize()
            }
        }
        .frame(maxWidth: fillsSpace ? .infinity : Self.width, maxHeight: fillsSpace ? .infinity : nil)
        // The clock only runs while there is data: with no sample the model
        // is already cleared and there is nothing to smooth or decay, so an
        // idle meter does not redraw. The id restarts the loop when data returns.
        .task(id: sample == nil) {
            guard sample != nil else { return }
            // Feed on a clock rather than on frame changes: equal successive
            // samples must still advance smoothing and peak decay.
            let clock = ContinuousClock()
            while !Task.isCancelled {
                if sample != nil || model.smoothed != nil {
                    model.update(sample, at: clock.now)
                }
                try? await clock.sleep(for: Self.tick)
            }
        }
        .onChange(of: readout.acceleration, initial: true) { _, new in
            sample = new
            // Apply at once rather than on the next tick: a new sample shows
            // without a dash frame, and missing data clears immediately.
            if new != nil || model.smoothed != nil { model.update(new, at: .now) }
        }
        .onChange(of: model.ringRange) {
            // Only a change the driver can see while data is live; a reset to
            // the compact range on missing data is not announced.
            guard !reduceMotion, readout.acceleration != nil, model.dot != nil else { return }
            withAnimation(Self.highlightRise) {
                rangeHighlight = 1
            } completion: {
                withAnimation(Self.highlightFade) { rangeHighlight = 0 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.gMeterAccessibilityText(model.smoothed))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("drive.gmeter")
    }

    private func titleRow(live: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text("G-METER")
                .font(Theme.DriveTypography.label(10))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(DriveReadout.gMeterRangeText(model.ringRange))
                .font(Theme.DriveTypography.label(9))
                .monospacedDigit()
                // `rangeHighlight` jumps to its target inside `withAnimation`, so
                // this reads "rising, not fading" rather than the current glow.
                .foregroundStyle(rangeHighlight == 1 ? Theme.Colors.accent : (live ? Theme.Colors.textTertiary : Theme.Colors.textDisabled))
                .scaleEffect(1 + 0.2 * rangeHighlight, anchor: .leading)
                // A cross-fade rather than rolling digits, which pass through a
                // misleading "±1.5" on the way from 0.5 to 1.0.
                .contentTransition(reduceMotion ? .identity : .opacity)
                .animation(reduceMotion ? nil : Self.rangeAnimation, value: model.ringRange)
        }
        .lineLimit(1)
    }

    @ViewBuilder private func valueRow(live: Bool, size valueSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
            Text(readout.gMeterValueText(model.smoothed))
                .font(Theme.DriveTypography.numerals(valueSize))
                .foregroundStyle(live ? Theme.Colors.textPrimary : Theme.Colors.textDisabled)
                .monospacedDigit()
            if let status = readout.gMeterStatusText {
                Text(status)
                    .font(Theme.DriveTypography.label(valueSize * 0.4))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .minimumScaleFactor(0.7)
            } else if face == .rings {
                Text("G")
                    .font(Theme.DriveTypography.label(valueSize * 0.45))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .lineLimit(1)
    }
}

/// The dial itself, drawn from the model's presentation values (g, x right,
/// y up) on a rim of `range` g.
///
/// `range` animates on its own while the model keeps updating, so a range
/// change rescales the dot, peaks, trail and marks smoothly. Positions are
/// clamped again to the drawn range, which lags the model's while expanding.
private struct GMeterFace: View, Animatable {
    let model: GMeterModel
    var range: Double
    /// 0…1: the accent glow on the rim after a range change.
    var highlight: Double
    let live: Bool
    /// Trail and glow; off under Reduce Motion. The dot and peaks still update.
    let showsMotion: Bool
    let face: MotorsportGMeter.Face

    /// How far the torch's light reaches from the dot, as a share of the
    /// ring's radius. The torch face draws this far past the ring, so the
    /// light is not cut off when the dot sits on the rim.
    private static let torchReach: CGFloat = 0.75

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(range, highlight) }
        set { (range, highlight) = (newValue.first, newValue.second) }
    }

    var body: some View {
        GeometryReader { proxy in
            let bleed = face == .torch ? min(proxy.size.width, proxy.size.height) / 2 * Self.torchReach : 0
            canvas(bleed: bleed)
                .frame(width: proxy.size.width + 2 * bleed, height: proxy.size.height + 2 * bleed)
                .offset(x: -bleed, y: -bleed)
        }
        .accessibilityHidden(true)
    }

    /// The dial, `bleed` larger than its frame on every side.
    private func canvas(bleed: CGFloat) -> some View {
        Canvas { context, size in
            let ring = min(size.width, size.height) - 2 * bleed
            // Strokes, ticks and the dot grow with the ring past its corner size.
            let k = max(1, ring / MotorsportGMeter.ringDiameter)
            let radius = ring / 2 - 2 * k
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ p: GMeterModel.Point) -> CGPoint {
                let p = p.clamped(toRadius: range)
                return CGPoint(x: center.x + CGFloat(p.x / range) * radius, y: center.y - CGFloat(p.y / range) * radius)
            }
            func circle(_ r: CGFloat, at c: CGPoint = center) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }

            let markColor = live ? Theme.Colors.textDisabled : Theme.Colors.surfaceRaised
            let torch = face == .torch
            if torch, live, let dot = model.dot {
                drawTorch(in: context, size: size, at: point(dot), center: center, radius: radius)
            }
            // Crosshair, the dashed inner mark for the range, then the rim.
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - radius, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - radius))
            cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            if !torch {
                context.stroke(cross, with: .color(Theme.Colors.surfaceRaised), lineWidth: k)
            }
            for mark in model.configuration.innerMarks(atRange: range) where !torch && mark.opacity > 0.01 && mark.value < range {
                context.stroke(
                    circle(radius * CGFloat(mark.value / range)),
                    with: .color(markColor.opacity(mark.opacity)),
                    style: StrokeStyle(lineWidth: k, dash: [2 * k, 3 * k])
                )
            }
            if !torch {
                context.stroke(circle(radius), with: .color(markColor), lineWidth: 1.5 * k)
            }
            if !torch, highlight > 0 {
                context.stroke(circle(radius), with: .color(Theme.Colors.accent.opacity(highlight)), lineWidth: (1.5 + highlight) * k)
            }
            if torch {
                drawPeakRim(in: context, center: center, radius: radius, ring: ring)
            }

            guard live, let dot = model.dot else { return }

            // Peak markers: short ticks across each axis at the held maximum.
            for direction in GMeterModel.PeakDirection.allCases where model.peaks[direction] > 0.05 {
                let at = point(model.peakPosition(direction))
                let horizontal = direction == .left || direction == .right
                var tick = Path()
                if horizontal {
                    tick.move(to: CGPoint(x: at.x, y: at.y - 4 * k))
                    tick.addLine(to: CGPoint(x: at.x, y: at.y + 4 * k))
                } else {
                    tick.move(to: CGPoint(x: at.x - 4 * k, y: at.y))
                    tick.addLine(to: CGPoint(x: at.x + 4 * k, y: at.y))
                }
                context.stroke(tick, with: .color(Theme.Colors.signalYellow), style: StrokeStyle(lineWidth: 2 * k, lineCap: .round))
            }

            // The torch's dot is smaller, and its trail with it.
            let dotScale: CGFloat = torch ? 0.55 : 1
            if showsMotion {
                let window = Self.seconds(model.configuration.trailWindow)
                for sample in model.trail.dropLast() {
                    let fade = max(0, 1 - Self.seconds(sample.age) / window)
                    context.fill(
                        circle((2 + 2 * fade) * k * dotScale, at: point(sample.position)),
                        with: .color(Theme.Colors.accent.opacity(0.5 * fade))
                    )
                }
            }

            let dotCenter = point(dot)
            if showsMotion {
                var glow = context
                glow.addFilter(.shadow(color: Theme.Colors.accent.opacity(0.8), radius: 6 * k))
                glow.fill(circle(6 * k * dotScale, at: dotCenter), with: .color(Theme.Colors.accent))
            } else {
                context.fill(circle(6 * k * dotScale, at: dotCenter), with: .color(Theme.Colors.accent))
            }
        }
    }

    /// The torch face's rim: a thin ring with each direction's held peak set
    /// on it, at the edge that direction pushes the dot to, in a gap cut
    /// into the line.
    private func drawPeakRim(in context: GraphicsContext, center: CGPoint, radius: CGFloat, ring: CGFloat) {
        let fontSize = (ring * 0.075).rounded()
        let margin = fontSize * 0.4
        // Screen directions (x right, y down) each peak's dot moves in.
        let sign: CGFloat = model.configuration.dotDirection == .feltForce ? -1 : 1
        func direction(_ peak: GMeterModel.PeakDirection) -> CGVector {
            switch peak {
            case .accel: CGVector(dx: 0, dy: -sign)
            case .brake: CGVector(dx: 0, dy: sign)
            case .left: CGVector(dx: -sign, dy: 0)
            case .right: CGVector(dx: sign, dy: 0)
            }
        }

        var gaps: [(angle: CGFloat, half: CGFloat)] = []
        for peak in GMeterModel.PeakDirection.allCases {
            let value = model.peaks[peak]
            let label = context.resolve(
                Text(live ? String(format: "%.2f", value) : "—")
                    .font(Theme.DriveTypography.academy(fontSize))
                    .foregroundStyle(.white.opacity(live && value > 0.05 ? 0.9 : 0.45))
            )
            let measured = label.measure(in: CGSize(width: ring, height: ring))
            let way = direction(peak)
            let at = CGPoint(x: center.x + way.dx * radius, y: center.y + way.dy * radius)
            context.draw(label, at: at, anchor: .center)
            // A label on the sides sits across the line, so its height cuts it.
            let along = way.dx == 0 ? measured.width : measured.height
            gaps.append((atan2(way.dy, way.dx), asin(min(1, (along / 2 + margin) / radius))))
        }

        var rim = Path()
        let sorted = gaps.sorted { $0.angle < $1.angle }
        for (index, gap) in sorted.enumerated() {
            let next = sorted[(index + 1) % sorted.count]
            var end = next.angle - next.half
            let start = gap.angle + gap.half
            if end < start { end += 2 * .pi }
            // Each arc is its own subpath, so the gaps are not bridged.
            rim.move(to: CGPoint(x: center.x + cos(start) * radius, y: center.y + sin(start) * radius))
            rim.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        }
        let lineWidth = max(1, ring / MotorsportGMeter.ringDiameter)
        context.stroke(rim, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        if highlight > 0 {
            context.stroke(rim, with: .color(Theme.Colors.accent.opacity(highlight)), style: StrokeStyle(lineWidth: lineWidth + highlight, lineCap: .round))
        }
    }

    /// The torch: a soft pool of the dot's colour and the triangle lattice
    /// lit around the dot, fading to nothing at the light's reach. The
    /// lattice is fixed to the dial; only the light moves.
    private func drawTorch(in context: GraphicsContext, size: CGSize, at light: CGPoint, center: CGPoint, radius: CGFloat) {
        let reach = radius * Self.torchReach
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [Theme.Colors.accent.opacity(0.22), Theme.Colors.accent.opacity(0)]),
                center: light, startRadius: 0, endRadius: reach
            )
        )
        context.stroke(
            Self.lattice(around: light, reach: reach, center: center, side: radius / 3.5),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.75), location: 0),
                    .init(color: .white.opacity(0.3), location: 0.55),
                    .init(color: .white.opacity(0), location: 1)
                ]),
                center: light, startRadius: 0, endRadius: reach
            ),
            style: StrokeStyle(lineWidth: 1, lineCap: .round)
        )
    }

    /// The lattice's edges within `reach` of `light`: a grid of equilateral
    /// triangles of `side`, anchored at `center`, with about a third of its
    /// edges left out by a fixed hash, so it reads as loose triangles and
    /// diamonds rather than a full grid.
    private static func lattice(around light: CGPoint, reach: CGFloat, center: CGPoint, side: CGFloat) -> Path {
        let rowHeight = side * 3.squareRoot() / 2
        func point(_ i: Int, _ j: Int) -> CGPoint {
            CGPoint(x: center.x + (CGFloat(i) + CGFloat(j) / 2) * side, y: center.y + CGFloat(j) * rowHeight)
        }
        func kept(_ i: Int, _ j: Int, _ direction: Int) -> Bool {
            var hash = UInt32(truncatingIfNeeded: i &* 73_856_093 ^ j &* 19_349_663 ^ direction &* 83_492_791)
            hash ^= hash >> 13
            hash &*= 0x5bd1_e995
            hash ^= hash >> 15
            return hash % 100 < 65
        }
        let jRange = Int(((light.y - center.y - reach) / rowHeight).rounded(.down)) - 1
            ... Int(((light.y - center.y + reach) / rowHeight).rounded(.up)) + 1
        var path = Path()
        for j in jRange {
            let rowShift = CGFloat(j) / 2
            let iLow = Int(((light.x - center.x - reach) / side - rowShift).rounded(.down)) - 1
            let iHigh = Int(((light.x - center.x + reach) / side - rowShift).rounded(.up)) + 1
            for i in iLow...iHigh {
                let from = point(i, j)
                // Right, down-right and down-left.
                for (direction, to) in [point(i + 1, j), point(i, j + 1), point(i - 1, j + 1)].enumerated() {
                    let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    guard hypot(middle.x - light.x, middle.y - light.y) < reach + side / 2,
                          kept(i, j, direction) else { continue }
                    path.move(to: from)
                    path.addLine(to: to)
                }
            }
        }
        return path
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
