import SwiftUI
import DesignSystem
import BLETransport
import CompanionProtocol
import CompanionLink

/// The default Drive presentation: a read-only, landscape Motorsport display
/// following the "04 · Drive" draft.
struct MotorsportDriveView: View {
    let readout: DriveReadout
    let onExit: () -> Void

    var body: some View {
        let hazardActive = readout.hazard.value == "On"
        let leftActive = hazardActive || readout.turn.value == "Left" || readout.turn.value == "Both"
        let rightActive = hazardActive || readout.turn.value == "Right" || readout.turn.value == "Both"
        DriveScreen(
            slots: DriveScreenSlots(
                backdrop: { MotorsportTurnGlow(left: leftActive, right: rightActive) },
                shiftLights: { MotorsportShiftLights(readout: readout) },
                leftIndicator: { MotorsportTurnArrow(
                    direction: .left,
                    active: leftActive,
                    freshness: readout.turn.freshness
                ) },
                rightIndicator: { MotorsportTurnArrow(
                    direction: .right,
                    active: rightActive,
                    freshness: readout.turn.freshness
                ) },
                rpm: { MotorsportRPM(readout: readout) },
                speed: { MotorsportMetric(
                    title: "KM/H",
                    value: readout.speedDisplayText,
                    alignment: .trailing,
                    accessibilityText: readout.speedAccessibilityText,
                    identifier: "drive.speed"
                ) },
                gear: { MotorsportGear(readout: readout) },
                sideMeters: { MotorsportSideMeters(readout: readout) },
                auxiliary: { MotorsportBoostPlaceholder(readout: readout) },
                link: { MotorsportLink(readout: readout) }
            ),
            onExit: onExit
        )
        .onAppear { Theme.DriveTypography.registerFonts() }
    }
}

// MARK: - Shift lights and indicators

private struct MotorsportShiftLights: View {
    let readout: DriveReadout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let count = PitWallReadout.shiftLightCount
            let spacing = min(12, proxy.size.width / CGFloat(count) * 0.3)
            let diameter = min(
                proxy.size.height,
                (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            )
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    let isLit = index < readout.litShiftLights
                    let isRed = readout.firstRedShiftLight.map { index >= $0 } ?? false
                    let color = isRed ? Theme.Colors.accent : Theme.Colors.signalGreen
                    Circle()
                        .fill(isLit ? color : Theme.Colors.surfaceRaised)
                        .frame(width: diameter, height: diameter)
                        .shadow(
                            color: color.opacity(isLit && !reduceMotion ? 0.7 : 0),
                            radius: isLit && !reduceMotion ? 8 : 0
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.12), value: readout.litShiftLights)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shift lights, \(readout.litShiftLights) of \(PitWallReadout.shiftLightCount) lit")
        .accessibilityIdentifier("drive.shift-lights")
    }
}

private struct MotorsportTurnArrow: View {
    enum Direction {
        case left, right

        var title: String {
            switch self {
            case .left: "Left turn"
            case .right: "Right turn"
            }
        }
    }

    let direction: Direction
    let active: Bool
    let freshness: PitWallReadout.Freshness
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BlockArrow()
            .fill(active ? Theme.Colors.signalYellow : Theme.Colors.surfaceRaised)
            .scaleEffect(x: direction == .left ? -1 : 1)
            .frame(width: 64, height: 44)
            .shadow(
                color: Theme.Colors.signalYellow.opacity(active && !reduceMotion ? 0.6 : 0),
                radius: active && !reduceMotion ? 10 : 0
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(direction.title), \(active ? "on" : "off"), \(freshness.title)")
            .accessibilityIdentifier(direction == .left ? "drive.turn.left" : "drive.turn.right")
    }
}

/// Amber washing in from the screen edge on the side that is signalling,
/// fading out about a quarter of the way across, and pulsing.
private struct MotorsportTurnGlow: View {
    let left: Bool
    let right: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if left { glow(from: .leading, to: UnitPoint(x: 0.26, y: 0.5)) }
            if right { glow(from: .trailing, to: UnitPoint(x: 0.74, y: 0.5)) }
        }
        .animation(.easeOut(duration: 0.2), value: left)
        .animation(.easeOut(duration: 0.2), value: right)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func glow(from start: UnitPoint, to end: UnitPoint) -> some View {
        let gradient = LinearGradient(
            colors: [Theme.Colors.signalYellow.opacity(0.32), Theme.Colors.signalYellow.opacity(0)],
            startPoint: start,
            endPoint: end
        )
        if reduceMotion {
            gradient.opacity(0.6).transition(.opacity)
        } else {
            gradient
                .phaseAnimator([1.0, 0.25]) { content, phase in
                    content.opacity(phase)
                } animation: { _ in
                    .easeInOut(duration: 0.4)
                }
                .transition(.opacity)
        }
    }
}

/// A right-pointing block arrow: a shaft and a triangular head.
private struct BlockArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let headStart = rect.maxX - rect.width * 0.42
        let shaftTop = rect.minY + rect.height * 0.3
        let shaftBottom = rect.maxY - rect.height * 0.3
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: shaftTop))
        path.addLine(to: CGPoint(x: headStart, y: shaftTop))
        path.addLine(to: CGPoint(x: headStart, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: headStart, y: rect.maxY))
        path.addLine(to: CGPoint(x: headStart, y: shaftBottom))
        path.addLine(to: CGPoint(x: rect.minX, y: shaftBottom))
        path.closeSubpath()
        return path
    }
}

// MARK: - Numerals

/// A small mono label over a numeral. Drive shows no freshness words:
/// values that are not current clear to a dash instead.
private struct MotorsportLabelRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.DriveTypography.label(11))
            .tracking(1.6)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
    }
}

private struct MotorsportRPM: View {
    let readout: DriveReadout
    @Environment(\.driveMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            MotorsportLabelRow(title: "RPM")
            Text(readout.rpmDisplayText)
                .font(Theme.DriveTypography.numerals(metrics.numeralSize))
                .foregroundStyle(rpmColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .driveNumeralLineHeight(metrics.numeralSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.rpmAccessibilityText)
        .accessibilityIdentifier("drive.rpm")
    }

    /// The numeral turns red past the redline, standing in for the removed bar.
    private var rpmColor: Color {
        if readout.rpm == nil { return Theme.Colors.textDisabled }
        return readout.redlineActive ? Theme.Colors.accent : Theme.Colors.textPrimary
    }
}

private struct MotorsportMetric: View {
    let title: String
    let value: String
    var alignment: HorizontalAlignment = .leading
    let accessibilityText: String
    let identifier: String
    @Environment(\.driveMetrics) private var metrics

    var body: some View {
        VStack(alignment: alignment, spacing: Theme.Spacing.xs) {
            MotorsportLabelRow(title: title)
            Text(value)
                .font(Theme.DriveTypography.numerals(metrics.numeralSize))
                .foregroundStyle(value == "—" ? Theme.Colors.textDisabled : Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .driveNumeralLineHeight(metrics.numeralSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(identifier)
    }
}

private extension View {
    /// Barlow's line box is far taller than its figures; trim it so numerals
    /// sit tight against their labels as in the draft.
    func driveNumeralLineHeight(_ size: CGFloat) -> some View {
        padding(.vertical, -size * 0.14)
    }
}

// MARK: - Centre gauges

private struct MotorsportGear: View {
    let readout: DriveReadout
    @Environment(\.driveMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The selector shown in place of the gear while it changes, or nil.
    @State private var flyInSelector: String?
    @State private var flyInTask: Task<Void, Never>?

    /// A known selector position, or nil while unknown, shifting or stale.
    private var selector: String? {
        guard readout.gearFreshness.showsValue, let selector = readout.selector,
              MotorsportSelectorStrip.order.contains(selector) else { return nil }
        return selector
    }

    var body: some View {
        let size = min(240, metrics.gaugeHeight * 0.74)
        let showsSelector = flyInSelector != nil
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("GEAR")
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(readout.selectorDisplayText)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fontWeight(.bold)
            }
            .font(Theme.DriveTypography.label(11))
            .tracking(1.6)
            Text(readout.gearDisplayText)
                .font(Theme.DriveTypography.numerals(size))
                .foregroundStyle(readout.gear == nil ? Theme.Colors.textDisabled : Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .driveNumeralLineHeight(size)
                .scaleEffect(showsSelector && !reduceMotion ? 0.6 : 1)
                .opacity(showsSelector ? 0 : 1)
                .overlay {
                    if let flyInSelector {
                        MotorsportSelectorStrip(current: flyInSelector, size: size)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .scale(scale: 1.6).combined(with: .opacity)
                            )
                    }
                }
        }
        .onChange(of: selector) { old, new in
            guard let old, let new, old != new else { return }
            showSelector(from: old, to: new)
        }
        .onDisappear { flyInTask?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.gearAccessibilityText)
        .accessibilityIdentifier("drive.gear")
        // Keep the gear clear of the side gauges' arcs and captions.
        .padding(.horizontal, MotorsportSideMeters.signalWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Flies the selector in over the gear, slides it to the new position,
    /// holds it briefly, then flies it back out. A change while it shows
    /// slides on from where it is and restarts the hold.
    private func showSelector(from old: String, to new: String) {
        flyInTask?.cancel()
        flyInTask = Task { @MainActor in
            if flyInSelector == nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { flyInSelector = old }
                try? await Task.sleep(for: .milliseconds(220))
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.75)) {
                flyInSelector = new
            }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { flyInSelector = nil }
        }
    }
}

/// The selector positions in a row with the current one large and its
/// neighbours small and dim. Changing `current` slides the row.
private struct MotorsportSelectorStrip: View {
    /// Left to right as drawn by the owner: at N, D sits left and R right.
    static let order = ["D", "N", "R", "P"]

    let current: String
    let size: CGFloat

    var body: some View {
        let currentIndex = Self.order.firstIndex(of: current) ?? 0
        ZStack {
            ForEach(Array(Self.order.enumerated()), id: \.element) { index, letter in
                let distance = index - currentIndex
                Text(letter)
                    .font(Theme.DriveTypography.numerals(size))
                    .foregroundStyle(distance == 0 ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .scaleEffect(distance == 0 ? 1 : 0.36)
                    .offset(x: CGFloat(distance) * size * 0.5)
                    .opacity(distance == 0 ? 1 : (abs(distance) == 1 ? 0.55 : 0))
                    .fixedSize()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MotorsportSideMeters: View {
    /// Width each side gauge (arc and its caption) takes from the centre column.
    static let signalWidth: CGFloat = 84

    let readout: DriveReadout

    var body: some View {
        let brakeKnown = readout.brake.value != nil
        let brakeOn = readout.brake.value == "Pressed"
        HStack(spacing: 0) {
            MotorsportSideSignal(
                title: "BRK",
                value: brakeKnown ? (brakeOn ? "ON" : "OFF") : "—",
                color: Theme.Colors.accent,
                fill: brakeOn ? 1 : 0,
                tag: nil,
                mirrored: false,
                accessibilityText: readout.brakeAccessibilityText,
                identifier: "drive.brake"
            )
            Spacer(minLength: 0)
            // No throttle signal yet: show the empty track, labelled.
            MotorsportSideSignal(
                title: "THR",
                value: "—",
                color: Theme.Colors.signalGreen,
                fill: 0,
                tag: readout.throttleDisplayText,
                mirrored: true,
                accessibilityText: readout.throttleAccessibilityText,
                identifier: "drive.throttle"
            )
        }
    }
}

private struct MotorsportSideSignal: View {
    let title: String
    let value: String
    let color: Color
    /// Lit share of the arc from the bottom, `0...1`.
    let fill: Double
    let tag: String?
    let mirrored: Bool
    let accessibilityText: String
    let identifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lit = fill > 0
        HStack(alignment: .bottom, spacing: Theme.Spacing.xxs) {
            if mirrored { caption(alignment: .trailing, lit: lit) }
            // An outlined tube along the arc, filled from the bottom.
            ZStack {
                GaugeArc(part: .ticks)
                    .stroke(Theme.Colors.textDisabled, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                GaugeArc(part: .tube)
                    .fill(Theme.Colors.surface)
                GaugeArc(part: .arc)
                    .trim(from: 0, to: fill)
                    .stroke(color, style: StrokeStyle(lineWidth: GaugeArc.tubeWidth - 4, lineCap: .butt))
                    .shadow(color: color.opacity(lit && !reduceMotion ? 0.7 : 0), radius: lit && !reduceMotion ? 8 : 0)
                GaugeArc(part: .border)
                    .stroke(
                        lit ? color : Theme.Colors.textDisabled,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
            }
            .scaleEffect(x: mirrored ? -1 : 1)
            .frame(width: 44)
            if !mirrored { caption(alignment: .leading, lit: lit) }
        }
        .frame(width: MotorsportSideMeters.signalWidth)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: fill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(identifier)
    }

    private func caption(alignment: HorizontalAlignment, lit: Bool) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .font(Theme.DriveTypography.numerals(24))
                .foregroundStyle(lit ? color : (value == "—" ? Theme.Colors.textDisabled : Theme.Colors.textSecondary))
            Text(title)
                .font(Theme.DriveTypography.label(10))
                .tracking(1.2)
                .foregroundStyle(lit ? color : Theme.Colors.textTertiary)
            if let tag {
                Text(tag)
                    .font(Theme.DriveTypography.label(8))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .minimumScaleFactor(0.6)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .bottom))
    }
}

/// A "(" shaped arc of a circle, drawn bottom to top so `trim` fills it
/// upwards; the tube around it, for the outline; or quarter ticks on its
/// outer side. The arc bows to the left; mirror it for the right-hand gauge.
private struct GaugeArc: Shape {
    /// The centre line, the whole tube, the tube's open outline (both ends
    /// and the outer edge, leaving the side facing the gear open), or ticks.
    enum Part { case arc, tube, border, ticks }

    static let tubeWidth: CGFloat = 12
    let part: Part
    private let tickLength: CGFloat = 6
    private let tickGap: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let half = Self.tubeWidth / 2
        let inset = tickLength + tickGap + half
        let sagitta = max(1, rect.width - inset - half - 1)
        let halfChord = rect.height / 2
        let radius = (halfChord * halfChord + sagitta * sagitta) / (2 * sagitta)
        let center = CGPoint(x: rect.minX + inset + radius, y: rect.midY)
        let sweep = Double(asin(min(1, halfChord / radius)))

        func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
            CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
        }

        var path = Path()
        if part == .ticks {
            for share in [0.25, 0.5, 0.75] {
                let angle = .pi + sweep - 2 * sweep * share
                path.move(to: point(angle, radius + half + tickGap))
                path.addLine(to: point(angle, radius + half + tickGap + tickLength))
            }
            return path
        }
        let steps = 48
        if part == .border {
            let ends = (Double.pi + sweep, Double.pi - sweep)
            path.move(to: point(ends.0, radius - half))
            for step in 0...steps {
                let angle = ends.0 - 2 * sweep * Double(step) / Double(steps)
                path.addLine(to: point(angle, radius + half))
            }
            path.addLine(to: point(ends.1, radius - half))
            return path
        }
        for step in 0...steps {
            let angle = .pi + sweep - 2 * sweep * Double(step) / Double(steps)
            let p = point(angle, radius)
            step == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        if part == .tube {
            return path.strokedPath(StrokeStyle(lineWidth: Self.tubeWidth, lineCap: .butt))
        }
        return path
    }
}

// MARK: - Boost and link

private struct MotorsportBoostPlaceholder: View {
    let readout: DriveReadout

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("BOOST")
                    .font(Theme.DriveTypography.label(10))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(readout.boostDisplayText)
                    .font(Theme.DriveTypography.label(8))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.xs)
                            .stroke(Theme.Colors.textDisabled, lineWidth: 1)
                    }
            }
            BoostDial()
                .stroke(Theme.Colors.surfaceRaised, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 104, height: 52)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("—")
                    .font(Theme.DriveTypography.numerals(20))
                    .foregroundStyle(Theme.Colors.textDisabled)
                Text("BAR")
                    .font(Theme.DriveTypography.label(9))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xs)
                .stroke(Theme.Colors.textDisabled, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.boostAccessibilityText)
        .accessibilityIdentifier("drive.boost")
    }
}

/// An empty half dial with ticks; there is no boost signal to drive a needle.
private struct BoostDial: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width / 2, rect.height) - 2
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        for step in 0...8 {
            let angle = Double.pi + Double.pi * Double(step) / 8
            let outer = radius - 6
            let inner = radius - (step.isMultiple(of: 2) ? 12 : 9)
            path.move(to: CGPoint(x: center.x + outer * CGFloat(cos(angle)), y: center.y + outer * CGFloat(sin(angle))))
            path.addLine(to: CGPoint(x: center.x + inner * CGFloat(cos(angle)), y: center.y + inner * CGFloat(sin(angle))))
        }
        return path
    }
}

/// The controller link, set quietly under the gauges in place of the
/// draft's status strip.
private struct MotorsportLink: View {
    let readout: DriveReadout

    var body: some View {
        let live = readout.linkState.pillStatus == .live
        HStack(spacing: 6) {
            Circle()
                .fill(live ? Theme.Colors.signalTeal : Theme.Colors.textDisabled)
                .frame(width: 6, height: 6)
            Text(readout.linkDisplayText)
                .font(Theme.DriveTypography.label(9))
                .tracking(1.4)
                .foregroundStyle(live ? Theme.Colors.signalTeal.opacity(0.8) : Theme.Colors.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Link, \(readout.linkDisplayText)")
        .accessibilityIdentifier("drive.link")
    }
}

// MARK: - Previews

private enum MotorsportDrivePreview {
    static func readout(at seconds: Double, scenario: DemoScenario) -> DriveReadout {
        let frame: LiveSignalFrame
        switch scenario {
        case .stalled, .notPaired, .connecting:
            frame = .unknown
        default:
            frame = (try? LiveSignalFrame(decoding: DemoTelemetry.drive(at: seconds, sequence: 1).encoded)) ?? .unknown
        }
        let link: LinkState = scenario == .notPaired
            ? .unknown
            : .connected(.init(id: UUID(), name: "Demo Controller", maximumWriteLength: 182))
        let activeConfig = (try? ControllerConfig(canonicalJSON: DemoController.factoryDocument))
            .map { ConfigSummary($0, profile: .factory) }
        return DriveReadout(frame: frame, activeConfig: activeConfig, linkState: link)
    }
}

struct MotorsportDrive_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MotorsportDriveView(
                readout: MotorsportDrivePreview.readout(at: 4.5, scenario: .connected),
                onExit: {}
            )
            .preferredColorScheme(.dark)
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDisplayName("Moving demo")

            MotorsportDriveView(
                readout: MotorsportDrivePreview.readout(at: 4.5, scenario: .stalled),
                onExit: {}
            )
            .preferredColorScheme(.dark)
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDisplayName("Stalled")

            MotorsportDriveView(
                readout: MotorsportDrivePreview.readout(at: 0, scenario: .notPaired),
                onExit: {}
            )
            .preferredColorScheme(.dark)
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDisplayName("Not connected")
        }
    }
}
