import SwiftUI
import DesignSystem
import BLETransport
import CompanionProtocol
import CompanionLink

/// A digital-cluster Drive style: a blue speed bar bending around the left
/// of a faceted centre panel, a red RPM bar around the right, the speed and
/// gear inside them and the G-meter in the middle.
struct ClusterDriveView: View {
    let readout: DriveReadout
    let signals: MotorsportSignals
    /// The in-app RPM scale and redline, for the bar's numbers.
    let rpmBand: RPMBand
    let onExit: () -> Void
    var onSwitchStyle: (() -> Void)?

    var body: some View {
        DriveScreen(onExit: onExit, onSwitchStyle: onSwitchStyle) {
            Color.black
        } content: {
            ClusterDashboard(readout: readout, signals: signals, rpmBand: rpmBand)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("drive.cluster")
        }
    }
}

enum ClusterPalette {
    static let blue = Color(red: 0.12, green: 0.56, blue: 1.0)
    static let blueBright = Color(red: 0.62, green: 0.84, blue: 1.0)
    static let red = Color(red: 0.96, green: 0.13, blue: 0.22)
    static let redBright = Color(red: 1.0, green: 0.55, blue: 0.58)
    static let panelTop = Color(red: 0.04, green: 0.22, blue: 0.62)
    static let panelDeep = Color(red: 0.02, green: 0.15, blue: 0.47)
    static let facetTop = Color(red: 0.03, green: 0.19, blue: 0.55)
    static let facetDeep = Color(red: 0.01, green: 0.12, blue: 0.40)
    static let unit = Color(red: 0.55, green: 0.75, blue: 1.0)
}

// MARK: - Geometry

/// A "<" made of two straight segments, from the bottom through the apex to
/// the top. Its height runs straight down the screen, so a value maps to a
/// height and the scale's numbers are evenly spaced, as in the reference.
struct ClusterChevron {
    var top: CGPoint
    var apex: CGPoint
    var bottom: CGPoint

    func offset(_ dx: CGFloat) -> ClusterChevron {
        ClusterChevron(
            top: CGPoint(x: top.x + dx, y: top.y),
            apex: CGPoint(x: apex.x + dx, y: apex.y),
            bottom: CGPoint(x: bottom.x + dx, y: bottom.y)
        )
    }

    func mirrored(in width: CGFloat) -> ClusterChevron {
        ClusterChevron(
            top: CGPoint(x: width - top.x, y: top.y),
            apex: CGPoint(x: width - apex.x, y: apex.y),
            bottom: CGPoint(x: width - bottom.x, y: bottom.y)
        )
    }

    /// The chevron's x at a height between its top and bottom.
    func x(atY y: CGFloat) -> CGFloat {
        let (a, b) = y <= apex.y ? (top, apex) : (apex, bottom)
        guard b.y != a.y else { return a.x }
        return a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
    }

    func point(atY y: CGFloat) -> CGPoint { CGPoint(x: x(atY: y), y: y) }
}

/// Where everything sits. Positions are taken from the reference photo in
/// (u, v) shares: u runs from the left bar's apex to the right's, v from the
/// top of the bars to the bottom, so the bars, facets and readouts line up on
/// every phone.
struct ClusterGeometry: Equatable {
    let size: CGSize

    /// The reference cluster's width to height. Keeping it keeps the 60°
    /// stripes at 60° and the triangular facets equilateral, so the cluster
    /// stays this short rather than filling the screen's height.
    static let aspect: CGFloat = 1388.0 / 445.0

    var width: CGFloat { size.width }
    /// Distance between the two bars' apexes.
    /// As wide as leaves the speed scale's numbers on screen beside the
    /// left apex; the Dynamic Island may cover some of them.
    var span: CGFloat { min(width * 0.86, size.height * 0.84 * Self.aspect) }
    var top: CGFloat { (size.height - span / Self.aspect) / 2 }
    var bottom: CGFloat { top + span / Self.aspect }
    /// The two bars' apexes, where u is 0 and 1.
    var left: CGFloat { (width - span) / 2 }
    var right: CGFloat { width - left }

    func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: left + (right - left) * u, y: top + (bottom - top) * v)
    }

    var apexY: CGFloat { point(0, 0.387).y }
    /// Horizontal width of the track between a bar's outer and inner lines.
    var bandWidth: CGFloat { max(16, (right - left) * 0.05) }
    /// The black gap between a bar's inner line and the faceted interior.
    var gap: CGFloat { max(4, (right - left) * 0.009) }

    var leftOuter: ClusterChevron {
        // Both segments lean 60° from the horizontal.
        ClusterChevron(top: point(0.0716, 0), apex: point(0, 0.387), bottom: point(0.1136, 1))
    }

    var rightOuter: ClusterChevron { leftOuter.mirrored(in: width) }

    func outer(_ side: ClusterSide) -> ClusterChevron { side == .left ? leftOuter : rightOuter }

    /// The bar's inner line, a band's width toward the centre.
    /// The bar's inner line, a band's width toward the centre. As in the
    /// reference, it bends a little lower than the outer line.
    func inner(_ side: ClusterSide) -> ClusterChevron {
        var inner = outer(side).offset(side.inward * bandWidth)
        inner.apex.y += (bottom - top) * 0.05
        return inner
    }

    /// How round the bars' apexes are.
    var apexRadius: CGFloat { span * 0.012 }

    /// Where the bars end: the zero mark, a little above the bottom line.
    var barBottom: CGFloat { bottom - (bottom - top) * 0.035 }

    /// The bar's height for a fill share, from the zero mark up.
    func y(forFraction fraction: Double) -> CGFloat {
        barBottom - (barBottom - top) * CGFloat(min(1, max(0, fraction)))
    }

    /// The strip between the outer and inner lines, down to the zero mark,
    /// optionally inset from either line. At the top it follows the inner
    /// line's curve, a constant inset away, up into the top line.
    func band(_ side: ClusterSide, outerInset: CGFloat = 0, innerInset: CGFloat = 0) -> Path {
        let outer = outer(side).offset(side.inward * outerInset)
        let inner = inner(side).offset(-side.inward * innerInset)
        var path = Path()
        path.move(to: outer.point(atY: barBottom))
        path.addArc(tangent1End: outer.apex, tangent2End: outer.top, radius: apexRadius)
        path.addLine(to: outer.top)
        for point in shoulderOffsetCurve(side, inset: innerInset) { path.addLine(to: point) }
        path.addArc(tangent1End: inner.apex, tangent2End: inner.bottom, radius: apexRadius)
        path.addLine(to: inner.point(atY: barBottom))
        path.closeSubpath()
        return path
    }

    /// The inner line's top curve, pushed `inset` outward from its centre,
    /// from where it meets the top line down to where it joins the inset
    /// slant.
    private func shoulderOffsetCurve(_ side: ClusterSide, inset: CGFloat) -> [CGPoint] {
        let inner = inner(side)
        let corner = inner.top
        let r = shoulderRadius
        let dx = inner.apex.x - corner.x, dy = inner.apex.y - corner.y
        let length = hypot(dx, dy)
        let down = CGPoint(x: dx / length, y: dy / length)
        let along = CGPoint(x: side.inward, y: 0)
        // The curve's centre sits on the corner's bisector, r / sin 60° in.
        let bx = down.x + along.x, by = down.y + along.y
        let bl = hypot(bx, by)
        let centre = CGPoint(x: corner.x + bx / bl * r / sin(.pi / 3), y: corner.y + by / bl * r / sin(.pi / 3))
        let tangent = CGPoint(x: corner.x + down.x * r / sqrt(3), y: corner.y + down.y * r / sqrt(3))
        let radius = r + inset
        let endAngle = atan2(tangent.y - centre.y, tangent.x - centre.x)
        let rise = max(-1, min(1, (top - centre.y) / radius))
        let startAngle = side == .left ? .pi - asin(rise) : asin(rise)
        var sweep = endAngle - startAngle
        if sweep > .pi { sweep -= 2 * .pi }
        if sweep < -.pi { sweep += 2 * .pi }
        return (0...12).map { i in
            let angle = startAngle + sweep * CGFloat(i) / 12
            return CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        }
    }

    /// The lit bar's shape: the whole strip between the lines, carried
    /// below the zero mark and flaring into the bottom line, so a lit bar
    /// runs unbroken into it.
    func litBand(_ side: ClusterSide) -> Path {
        let outer = outer(side)
        let inner = inner(side)
        var path = Path()
        path.move(to: outer.top)
        path.addArc(tangent1End: outer.apex, tangent2End: outer.bottom, radius: apexRadius)
        path.addArc(tangent1End: outer.bottom, tangent2End: inner.bottom, radius: footRadius)
        path.addLine(to: innerFlareStart(side))
        path.addArc(tangent1End: inner.bottom, tangent2End: inner.apex, radius: footRadius)
        path.addArc(tangent1End: inner.apex, tangent2End: inner.top, radius: apexRadius)
        path.addArc(tangent1End: inner.top, tangent2End: outer.top, radius: shoulderRadius)
        path.closeSubpath()
        return path
    }

    /// Where the inner line curves into the top line.
    var shoulderRadius: CGFloat { span * 0.022 }
    /// Where the outer line curves into the bottom line.
    var footRadius: CGFloat { span * 0.016 }

    /// The outer line's stroke widths: light along the bottom and up to the
    /// apex, heavier from the apex up to the top corner.
    static let outerLowerWidth: CGFloat = 3
    static let outerUpperWidth: CGFloat = 4.5

    /// How far along each run from the apex the line's weight change
    /// reaches, either side of the apex curve.
    private var outerTaperReach: CGFloat { apexRadius / sqrt(3) + apexRadius * 2.5 }

    private func outerRuns(_ side: ClusterSide) -> (down: CGPoint, up: CGPoint) {
        let outer = outer(side)
        func unit(_ to: CGPoint) -> CGPoint {
            let dx = to.x - outer.apex.x, dy = to.y - outer.apex.y
            let length = hypot(dx, dy)
            return CGPoint(x: dx / length, y: dy / length)
        }
        return (unit(outer.bottom), unit(outer.top))
    }

    /// The outer line's light run: in along the bottom edge from the centre,
    /// curving up into the bar, to where the taper round the apex starts.
    func outerLowerLine(_ side: ClusterSide) -> Path {
        let outer = outer(side)
        let down = outerRuns(side).down
        var path = Path()
        path.move(to: CGPoint(x: width / 2 - side.inward * 3, y: outer.bottom.y))
        path.addArc(tangent1End: outer.bottom, tangent2End: outer.apex, radius: footRadius)
        path.addLine(to: CGPoint(
            x: outer.apex.x + down.x * outerTaperReach,
            y: outer.apex.y + down.y * outerTaperReach
        ))
        return path
    }

    /// The top line's width: as light as the inner line.
    static let topLineWidth: CGFloat = 2

    /// The outer line's heavy run as a filled shape: from where the taper
    /// ends up to the sharp top corner, mitred there into the lighter top
    /// line, which runs on toward the centre with a round end.
    func outerUpperLine(_ side: ClusterSide) -> Path {
        let outer = outer(side)
        let up = outerRuns(side).up
        let corner = outer.top
        let start = CGPoint(x: outer.apex.x + up.x * outerTaperReach, y: outer.apex.y + up.y * outerTaperReach)
        let end = CGPoint(x: width / 2 - side.inward * (width / 2 - point(0.305, 0).x), y: corner.y)
        let direction = CGPoint(x: corner.x - start.x, y: corner.y - start.y)
        let length = hypot(direction.x, direction.y)
        let d = CGPoint(x: direction.x / length, y: direction.y / length)
        // The slant's normal toward the track.
        let toTrack = side == .left ? CGPoint(x: -d.y, y: d.x) : CGPoint(x: d.y, y: -d.x)
        let slant = Self.outerUpperWidth / 2
        let rule = Self.topLineWidth / 2
        // Where the slant's edge, `offset` toward the track, meets y.
        func meet(_ offset: CGFloat, _ y: CGFloat) -> CGPoint {
            let from = CGPoint(x: corner.x + toTrack.x * offset, y: corner.y + toTrack.y * offset)
            let t = (y - from.y) / d.y
            return CGPoint(x: from.x + d.x * t, y: y)
        }
        var path = Path()
        path.addLines([
            CGPoint(x: start.x - toTrack.x * slant, y: start.y - toTrack.y * slant),
            meet(-slant, corner.y - rule),
            CGPoint(x: end.x, y: corner.y - rule),
            CGPoint(x: end.x, y: corner.y + rule),
            meet(slant, corner.y + rule),
            CGPoint(x: start.x + toTrack.x * slant, y: start.y + toTrack.y * slant)
        ])
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: end.x - rule, y: end.y - rule, width: rule * 2, height: rule * 2))
        return path
    }

    /// The outer line round its apex as a filled ribbon whose width eases
    /// from the light run's to the heavy run's, joining the two strokes.
    func outerApexTaper(_ side: ClusterSide) -> Path {
        let apex = outer(side).apex
        let (down, up) = outerRuns(side)
        let r = apexRadius
        let tangent = r / sqrt(3)
        // The apex curve's centre lies on the bisector, r / sin 60° in.
        let bisector = CGPoint(x: down.x + up.x, y: down.y + up.y)
        let bisectorLength = hypot(bisector.x, bisector.y)
        let centreDistance = r / sin(.pi / 3)
        let centre = CGPoint(
            x: apex.x + bisector.x / bisectorLength * centreDistance,
            y: apex.y + bisector.y / bisectorLength * centreDistance
        )
        let startTangent = CGPoint(x: apex.x + down.x * tangent, y: apex.y + down.y * tangent)
        let endTangent = CGPoint(x: apex.x + up.x * tangent, y: apex.y + up.y * tangent)
        let startAngle = atan2(startTangent.y - centre.y, startTangent.x - centre.x)
        var sweep = atan2(endTangent.y - centre.y, endTangent.x - centre.x) - startAngle
        if sweep > .pi { sweep -= 2 * .pi }
        if sweep < -.pi { sweep += 2 * .pi }

        var points: [CGPoint] = []
        let straight = outerTaperReach - tangent
        for i in 0..<8 {
            let along = tangent + straight * (1 - CGFloat(i) / 8)
            points.append(CGPoint(x: apex.x + down.x * along, y: apex.y + down.y * along))
        }
        for i in 0...12 {
            let angle = startAngle + sweep * CGFloat(i) / 12
            points.append(CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle)))
        }
        for i in 1...8 {
            let along = tangent + straight * CGFloat(i) / 8
            points.append(CGPoint(x: apex.x + up.x * along, y: apex.y + up.y * along))
        }

        // Cumulative length, for a smooth ease along the whole ribbon.
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }
        let total = lengths.last ?? 1
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in points.indices {
            let previous = points[max(0, i - 1)]
            let next = points[min(points.count - 1, i + 1)]
            let dx = next.x - previous.x, dy = next.y - previous.y
            let length = max(hypot(dx, dy), 0.0001)
            let normal = CGPoint(x: -dy / length, y: dx / length)
            let t = lengths[i] / total
            let ease = t * t * (3 - 2 * t)
            let half = (Self.outerLowerWidth + (Self.outerUpperWidth - Self.outerLowerWidth) * ease) / 2
            left.append(CGPoint(x: points[i].x + normal.x * half, y: points[i].y + normal.y * half))
            right.append(CGPoint(x: points[i].x - normal.x * half, y: points[i].y - normal.y * half))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    /// Where the inner line's flare into the bottom line begins: on the
    /// bottom line, just far enough in for a foot-radius curve to meet the
    /// 60° inner line.
    func innerFlareStart(_ side: ClusterSide) -> CGPoint {
        let inner = inner(side)
        return CGPoint(x: inner.bottom.x + side.inward * footRadius * sqrt(3), y: inner.bottom.y)
    }

    /// The inner line, flaring up out of the bottom line, round its apex,
    /// curving into the top line.
    func innerLine(_ side: ClusterSide) -> Path {
        let inner = inner(side)
        var path = Path()
        path.move(to: innerFlareStart(side))
        path.addArc(tangent1End: inner.bottom, tangent2End: inner.apex, radius: footRadius)
        path.addArc(tangent1End: inner.apex, tangent2End: inner.top, radius: apexRadius)
        path.addArc(
            tangent1End: inner.top,
            tangent2End: CGPoint(x: inner.top.x + side.inward * shoulderRadius * 4, y: inner.top.y),
            radius: shoulderRadius
        )
        path.addLine(to: CGPoint(x: inner.top.x + side.inward * shoulderRadius * 2, y: inner.top.y))
        return path
    }

    /// Everything inside both inner lines, less the black gap: the area the
    /// facets are cut from.
    var interior: Path {
        let left = inner(.left).offset(gap)
        let right = inner(.right).offset(-gap)
        let top = point(0, 0.081).y
        let bottom = point(0, 0.94).y
        return Path.rounded([
            left.point(atY: top), right.point(atY: top), right.apex,
            right.point(atY: bottom), left.point(atY: bottom), left.apex
        ], radius: 10)
    }

    /// Everything between the two bars' outer lines.
    var surround: Path {
        Path.rounded([
            leftOuter.top, rightOuter.top, rightOuter.apex,
            rightOuter.bottom, leftOuter.bottom, leftOuter.apex
        ], radius: 6)
    }

    /// The middle of the central facet, where the G-meter sits.
    var panelCentre: CGPoint { point(0.5, 0.52) }
}

enum ClusterSide: Equatable {
    case left, right

    /// The x direction toward the centre of the screen.
    var inward: CGFloat { self == .left ? 1 : -1 }
}

private extension Path {
    /// A closed polygon with its corners rounded.
    static func rounded(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let count = points.count
        let start = CGPoint(
            x: (points[count - 1].x + points[0].x) / 2,
            y: (points[count - 1].y + points[0].y) / 2
        )
        path.move(to: start)
        for index in 0..<count {
            path.addArc(tangent1End: points[index], tangent2End: points[(index + 1) % count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Dashboard

private struct ClusterDashboard: View {
    let readout: DriveReadout
    let signals: MotorsportSignals
    let rpmBand: RPMBand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Speed scale numbers: 30 apart up to 150, then 60 apart, each the same
    /// distance up the bar.
    static let speedMarks: [Double] = [0, 30, 60, 90, 120, 150, 210, 270, 330]

    var body: some View {
        GeometryReader { proxy in
            let geometry = ClusterGeometry(size: proxy.size)
            ZStack(alignment: .topLeading) {
                ClusterBackground(geometry: geometry)

                ClusterBar(
                    style: ClusterBar.Style(
                        geometry: geometry,
                        side: .left,
                        color: ClusterPalette.blue,
                        bright: ClusterPalette.blueBright,
                        marks: Self.speedMarks.enumerated().map { index, value in
                            ClusterBar.Mark(fraction: Double(index) / Double(Self.speedMarks.count - 1), label: String(Int(value)))
                        },
                        unit: "km/h",
                        redlineFraction: nil,
                        trackOpacity: 0.4
                    ),
                    fraction: speedFraction
                )
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: speedFraction)
                .accessibilityHidden(true)

                ClusterBar(
                    style: ClusterBar.Style(
                        geometry: geometry,
                        side: .right,
                        color: ClusterPalette.red,
                        bright: ClusterPalette.redBright,
                        marks: rpmMarks,
                        unit: "1/min ×1000",
                        redlineFraction: readout.redlineFraction,
                        trackOpacity: 0.16
                    ),
                    fraction: readout.rpm == nil ? 0 : readout.rpmFraction
                )
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: readout.rpmFraction)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(readout.rpmAccessibilityText)
                .accessibilityIdentifier("drive.rpm")

                speed(geometry)
                gear(geometry)
                gMeter(geometry)
            }
        }
        .onAppear { Theme.DriveTypography.registerFonts() }
    }

    /// Speed's share of the bar: evenly spaced marks, so linear between them.
    private var speedFraction: Double {
        guard let speed = readout.speedKPH.map(Double.init) else { return 0 }
        let marks = Self.speedMarks
        guard speed > 0 else { return 0 }
        guard let upper = marks.firstIndex(where: { $0 >= speed }) else { return 1 }
        let lower = upper - 1
        let within = (speed - marks[lower]) / (marks[upper] - marks[lower])
        return (Double(lower) + within) / Double(marks.count - 1)
    }

    /// One number per thousand RPM up to the in-app scale's top.
    private var rpmMarks: [ClusterBar.Mark] {
        let scale = max(rpmBand.fill?.to ?? 0, rpmBand.redline ?? 0)
        guard scale >= 1000 else { return [] }
        return (0...Int(scale / 1000)).map { thousand in
            ClusterBar.Mark(fraction: Double(thousand) * 1000 / scale, label: String(thousand))
        }
    }

    private func speed(_ geometry: ClusterGeometry) -> some View {
        let known = readout.speedKPH != nil
        return readoutStack(
            geometry,
            u: 0.207,
            value: Text(readout.speedDisplayText).monospacedDigit(),
            valueColor: known ? .white : Theme.Colors.textDisabled,
            caption: "km/h",
            captionColor: ClusterPalette.unit
        )
        .accessibilityLabel(readout.speedAccessibilityText)
        .accessibilityIdentifier("drive.speed")
    }

    private func gear(_ geometry: ClusterGeometry) -> some View {
        let shifting = signals.isShifting
        let known = readout.gear != nil && !shifting
        return readoutStack(
            geometry,
            u: 0.845,
            value: Text(readout.gearDisplayText(shifting: shifting)),
            valueColor: known ? .white : Theme.Colors.textDisabled,
            caption: readout.selectorDisplayText(shifting: shifting),
            captionColor: ClusterPalette.redBright
        )
        .accessibilityLabel(readout.gearAccessibilityText)
        .accessibilityIdentifier("drive.gear")
    }

    /// A numeral centred in its side's black strip, with a caption just
    /// below the strip, as the reference sets its speed and gear.
    private func readoutStack(
        _ geometry: ClusterGeometry,
        u: CGFloat,
        value: Text,
        valueColor: Color,
        caption: String,
        captionColor: Color
    ) -> some View {
        let size = ((geometry.bottom - geometry.top) * 0.24).rounded()
        let strip = geometry.point(u, ClusterBackground.numeralStrip)
        return ZStack {
            value
                .font(ClusterType.numerals(size))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: geometry.width * 0.2)
                // New Academy's caps sit a little below the middle of the line.
                .position(x: strip.x, y: strip.y - size * 0.03)
            Text(caption)
                .font(ClusterType.label(13))
                .foregroundStyle(captionColor)
                .position(geometry.point(u, 0.54))
        }
        .accessibilityElement(children: .ignore)
    }

    private func gMeter(_ geometry: ClusterGeometry) -> some View {
        let diameter = min(geometry.width * 0.27, (geometry.bottom - geometry.top) * 0.78)
        return MotorsportGMeter(readout: readout, face: .torch, fillsSpace: true)
            .padding(diameter * 0.06)
            .frame(width: diameter, height: diameter)
            .position(geometry.panelCentre)
    }
}

/// Numerals in a wide, heavy face, like a digital cluster's.
/// Every Cluster label is set in New Academy, the wide face the owner chose.
private enum ClusterType {
    static func numerals(_ size: CGFloat) -> Font {
        Theme.DriveTypography.academy(size)
    }

    static func scale(_ size: CGFloat) -> Font {
        Theme.DriveTypography.academy(size)
    }

    static func label(_ size: CGFloat) -> Font {
        Theme.DriveTypography.academy(size)
    }
}

// MARK: - Background

/// The reference's interior: navy facets cut apart by black "/" stripes,
/// a black strip across each side for the speed and the gear, and a lighter
/// central facet ruled with thin lines. Decorative and static.
private struct ClusterBackground: View {
    let geometry: ClusterGeometry

    /// Middle of the black strips the speed and gear sit in, as v.
    static let numeralStrip: CGFloat = 0.443

    /// A corner in the reference photo's pixels, whose bars' apexes sit at
    /// x 312 and 1700 and whose bars run from y 340 to 785, as (u, v).
    private static func photo(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: (x - 312) / 1388, y: (y - 340) / 445)
    }

    /// The side facets. Every slanted edge leans 60° (0.577 px across per
    /// px down), so the wedges are equilateral triangles. The black left
    /// between the facets and the interior's edge is the stripes and the
    /// numeral strips.
    private static let facets: [[CGPoint]] = [
        // Left: a narrow sliver, a wide facet above the speed, a wedge below.
        [photo(501, 377), photo(553, 377), photo(460.6, 537), photo(408.6, 537)],
        [photo(559, 377), photo(647, 377), photo(706.5, 480), photo(696.7, 497), photo(489.7, 497)],
        [photo(537, 577), photo(650, 577), photo(593.5, 674.9)],
        // Right: a facet above the gear, a triangle by the bar, a facet below.
        [photo(1442, 377), photo(1519, 377), photo(1561, 450), photo(1534.4, 496), photo(1373.3, 496)],
        [photo(1567, 460), photo(1610, 534.5), photo(1524, 534.5)],
        [photo(1328, 578), photo(1474, 578), photo(1374.1, 751), photo(1228.1, 751)]
    ]

    /// The central facet, leaning like the stripes either side of it.
    private static let panel: [CGPoint] = [
        photo(776, 377), photo(1434, 377), photo(1218, 751), photo(647.9, 751), photo(604, 675)
    ]

    /// Thin rules across the facets: a horizon, broken where the G-meter
    /// sits, and a few 60° diagonals. On the left the horizon ends in a
    /// corner with a "/" running down from it, just clear of the G-meter,
    /// and a "\" from further along it meets that "/" low down.
    private static let rules: [(CGPoint, CGPoint)] = [
        (photo(560, 497), photo(815, 497)),
        (photo(1192, 497), photo(1450, 497)),
        (photo(815, 497), photo(668.4, 751)),
        (photo(626, 497), photo(720.5, 660.8)),
        (photo(1114, 377), photo(1183.3, 497)),
        (photo(1183.3, 497), photo(1330, 751)),
        (photo(1306, 377), photo(1375.3, 497)),
        (photo(626, 497), photo(676.2, 410)),
        (photo(1433, 583), photo(1471.7, 650))
    ]

    var body: some View {
        Canvas { context, _ in
            let g = geometry
            func polygon(_ corners: [CGPoint], radius: CGFloat = 4) -> Path {
                Path.rounded(corners.map { g.point($0.x, $0.y) }, radius: radius)
            }

            context.fill(g.surround, with: .color(.black))

            var inside = context
            inside.clip(to: g.interior)
            let panel = polygon(Self.panel, radius: 8)
            var facets = Path()
            for corners in Self.facets { facets.addPath(polygon(corners)) }

            inside.fill(
                facets,
                with: .linearGradient(
                    Gradient(colors: [ClusterPalette.facetTop, ClusterPalette.facetDeep]),
                    startPoint: CGPoint(x: 0, y: g.top),
                    endPoint: CGPoint(x: 0, y: g.bottom)
                )
            )
            inside.fill(
                panel,
                with: .radialGradient(
                    Gradient(colors: [ClusterPalette.panelTop, ClusterPalette.panelDeep]),
                    center: g.panelCentre,
                    startRadius: 0,
                    endRadius: g.width * 0.35
                )
            )

            var ruled = inside
            var lit = facets
            lit.addPath(panel)
            ruled.clip(to: lit)
            var lines = Path()
            for (from, to) in Self.rules {
                lines.move(to: g.point(from.x, from.y))
                lines.addLine(to: g.point(to.x, to.y))
            }
            ruled.stroke(lines, with: .color(ClusterPalette.blueBright.opacity(0.22)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bars

/// One side's bar: the scale beside it, the band lit from the bottom up to
/// the value with a white cap, and the glowing outer line that carries on
/// across the top and bottom of the dashboard.
///
/// Drawn as four stacked canvases so only the parts that follow the value
/// redraw while it animates: the unlit track, the lit share, the lines and
/// scale, then the lit marks and the topper. The two static layers keep
/// their inputs between frames, so SwiftUI leaves them drawn.
private struct ClusterBar: View {
    struct Mark: Equatable {
        let fraction: Double
        let label: String
    }

    /// What every layer of one bar is drawn from, less the value.
    struct Style: Equatable {
        let geometry: ClusterGeometry
        let side: ClusterSide
        let color: Color
        let bright: Color
        let marks: [Mark]
        let unit: String
        /// Where the red zone starts, as a share of the bar, or nil for none.
        let redlineFraction: Double?
        /// How strongly the unlit track is tinted with the bar's colour.
        let trackOpacity: Double

        /// The black gap between the outer line and the tinted stripe,
        /// where the scale ticks sit.
        var stripeOffset: CGFloat { geometry.bandWidth * 0.32 }
        var fontSize: CGFloat { ((geometry.bottom - geometry.top) * 0.095).rounded() }

        func inRed(_ mark: Mark) -> Bool {
            redlineFraction.map { mark.fraction >= $0 } ?? false
        }

        func tick(_ mark: Mark) -> Path {
            let y = geometry.y(forFraction: mark.fraction)
            let x = geometry.outer(side).x(atY: y)
            var tick = Path()
            tick.move(to: CGPoint(x: x + side.inward * 4, y: y))
            tick.addLine(to: CGPoint(x: x + side.inward * max(8, stripeOffset - 3), y: y))
            return tick
        }

        /// A scale number beside its tick, outside the outer line.
        func drawLabel(_ mark: Mark, color: Color, in context: GraphicsContext) {
            let y = geometry.y(forFraction: mark.fraction)
            let x = geometry.outer(side).x(atY: y)
            let label = context.resolve(
                Text(mark.label).font(ClusterType.scale(fontSize)).foregroundStyle(color)
            )
            let anchor: UnitPoint = side == .left ? .trailing : .leading
            // New Academy has one weight; overprinting it a hair apart
            // gives the heavier numbers the reference uses.
            for nudge in [-0.6, 0, 0.6] as [CGFloat] {
                context.draw(label, at: CGPoint(x: x - side.inward * 9 + nudge, y: y), anchor: anchor)
            }
        }
    }

    let style: Style
    let fraction: Double

    var body: some View {
        ZStack {
            ClusterBarTrack(style: style).equatable()
            ClusterBarFill(style: style, fraction: fraction)
            ClusterBarFrame(style: style).equatable()
            ClusterBarTopper(style: style, fraction: fraction)
        }
        .allowsHitTesting(false)
    }
}

/// The unlit track: a tinted stripe with a black gap from the outer line
/// and a hairline from the inner one, as in the reference, and the red zone.
private struct ClusterBarTrack: View, Equatable {
    let style: ClusterBar.Style

    var body: some View {
        Canvas { context, _ in
            let g = style.geometry
            let stripe = g.band(style.side, outerInset: style.stripeOffset, innerInset: g.bandWidth * 0.1)
            context.fill(stripe, with: .color(style.color.opacity(style.trackOpacity)))
            if let redlineFraction = style.redlineFraction {
                var zone = context
                zone.clip(to: Path(CGRect(x: 0, y: 0, width: g.width, height: g.y(forFraction: redlineFraction))))
                zone.fill(stripe, with: .color(style.color.opacity(0.28)))
            }
        }
    }
}

/// The lit share, from the bottom line up to the value.
private struct ClusterBarFill: View, Animatable {
    let style: ClusterBar.Style
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            guard fraction > 0.001 else { return }
            let g = style.geometry
            let fillY = g.y(forFraction: fraction)
            context.clip(to: Path(CGRect(x: 0, y: fillY, width: g.width, height: g.size.height - fillY)))
            context.addFilter(.shadow(color: style.color.opacity(0.8), radius: 10))
            context.fill(
                g.litBand(style.side),
                with: .linearGradient(
                    Gradient(colors: [style.bright, style.color]),
                    startPoint: CGPoint(x: 0, y: g.bottom),
                    endPoint: CGPoint(x: 0, y: g.top)
                )
            )
        }
    }
}

/// The glowing lines, the scale unlit and the unit: everything over the lit
/// share that stays put while the value moves.
private struct ClusterBarFrame: View, Equatable {
    let style: ClusterBar.Style

    var body: some View {
        Canvas { context, _ in
            let g = style.geometry
            let side = style.side
            let color = style.color

            // Outer line, carried across the top and bottom edges, and the
            // inner line curving into the top one.
            var glow = context
            glow.addFilter(.shadow(color: color.opacity(0.9), radius: 6))
            // The outer line: light below the apex, easing heavier round it.
            glow.drawLayer { line in
                line.stroke(
                    g.outerLowerLine(side), with: .color(color),
                    style: StrokeStyle(lineWidth: ClusterGeometry.outerLowerWidth, lineCap: .round)
                )
                line.fill(g.outerApexTaper(side), with: .color(color))
                line.fill(g.outerUpperLine(side), with: .color(color))
            }
            glow.stroke(g.innerLine(side), with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // The scale: ticks in the gap inside the outer line, numbers
            // outside it. The topper layer lights the ones the bar reaches.
            for mark in style.marks {
                let hue = style.inRed(mark) ? ClusterPalette.red : color
                context.stroke(style.tick(mark), with: .color(hue), lineWidth: 2)
                style.drawLabel(mark, color: hue.opacity(0.45), in: context)
            }

            let outer = g.outer(side)
            let unitLabel = Text(style.unit)
                .font(ClusterType.label((style.fontSize * 0.75).rounded()))
                .foregroundStyle(color.opacity(0.8))
            context.draw(
                unitLabel,
                at: CGPoint(x: outer.top.x, y: outer.top.y - 4),
                anchor: side == .left ? .bottomLeading : .bottomTrailing
            )
        }
    }
}

/// The marks the bar has reached, lit over their unlit selves, and the
/// topper at the value.
private struct ClusterBarTopper: View, Animatable {
    let style: ClusterBar.Style
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let g = style.geometry
            let side = style.side

            if fraction > 0.001 {
                for mark in style.marks where mark.fraction <= fraction + 0.001 {
                    let inRed = style.inRed(mark)
                    let hue = inRed ? ClusterPalette.red : style.color
                    context.stroke(style.tick(mark), with: .color(.white.opacity(0.9)), lineWidth: 2)
                    var text = context
                    text.addFilter(.shadow(color: hue, radius: 6))
                    style.drawLabel(mark, color: inRed ? ClusterPalette.redBright : style.bright, in: text)
                }
            }

            // The topper, drawn over the scale ticks: a glowing white slab
            // across the bar, line to line, its ends cut along the bar's
            // lines, with a hairline black gap above and below it. At zero
            // it doubles as the bar's end mark.
            let topperWidth: CGFloat = 3
            let slabGap: CGFloat = 1
            let seat = max(g.y(forFraction: fraction), g.top + topperWidth + slabGap * 2)
            let capOuter = g.outer(side).offset(-side.inward * 2)
            let capInner = g.inner(side).offset(side.inward * 1.5)
            let capBottom = seat - slabGap
            let capTop = capBottom - topperWidth
            var cap = Path()
            cap.addLines([
                capOuter.point(atY: capTop), capInner.point(atY: capTop),
                capInner.point(atY: capBottom), capOuter.point(atY: capBottom)
            ])
            cap.closeSubpath()
            var capContext = context
            capContext.addFilter(.shadow(color: .white.opacity(0.8), radius: 4))
            capContext.fill(cap, with: .color(.white))
            var gaps = context
            var gapRows = Path()
            gapRows.addRect(CGRect(x: 0, y: capTop - slabGap, width: g.width, height: slabGap))
            gapRows.addRect(CGRect(x: 0, y: capBottom, width: g.width, height: slabGap))
            gaps.clip(to: gapRows)
            gaps.fill(g.band(side, outerInset: -2, innerInset: -1.5), with: .color(.black))
        }
    }
}

// MARK: - Previews

struct ClusterDrive_Previews: PreviewProvider {
    static var previews: some View {
        let telemetry = DemoTelemetry.drive(at: 4.5, sequence: 1)
        let frame = (try? LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: telemetry.layoutVersion)) ?? .unknown
        let readout = DriveReadout(frame: frame, rpmBand: AppConfig.default.rpmBand)
        ClusterDriveView(
            readout: readout,
            signals: MotorsportSignals(frame: frame, readout: readout),
            rpmBand: AppConfig.default.rpmBand,
            onExit: {}
        )
        .preferredColorScheme(.dark)
        .previewInterfaceOrientation(.landscapeLeft)
    }
}
