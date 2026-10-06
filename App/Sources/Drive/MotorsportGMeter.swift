import SwiftUI
import DesignSystem
import CompanionLink

/// A friction-circle g-meter for the Drive `auxiliary` slot: a ring with
/// 0.5 g and 1.0 g marks, a smoothed dot with a short fading trail, decaying
/// peak markers per direction and the total g underneath.
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

    let readout: DriveReadout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = GMeterModel()
    /// The latest sample, kept in state so the clock loop reads the current
    /// frame rather than the one captured when the task started.
    @State private var sample: GForce?

    var body: some View {
        let live = readout.acceleration != nil && model.dot != nil
        VStack(spacing: Theme.Spacing.xxs) {
            Text("G-METER")
                .font(Theme.DriveTypography.label(10))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            GMeterFace(model: model, live: live, showsMotion: !reduceMotion)
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
            valueRow(live: live)
        }
        .frame(width: Self.width)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.gMeterAccessibilityText(model.smoothed))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("drive.gmeter")
    }

    @ViewBuilder private func valueRow(live: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
            Text(readout.gMeterValueText(model.smoothed))
                .font(Theme.DriveTypography.numerals(20))
                .foregroundStyle(live ? Theme.Colors.textPrimary : Theme.Colors.textDisabled)
                .monospacedDigit()
            if let status = readout.gMeterStatusText {
                Text(status)
                    .font(Theme.DriveTypography.label(8))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .minimumScaleFactor(0.7)
            } else {
                Text("G")
                    .font(Theme.DriveTypography.label(9))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .lineLimit(1)
    }
}

/// The dial itself, drawn from the model's presentation values (g, x right,
/// y up, already clamped to the ring).
private struct GMeterFace: View {
    let model: GMeterModel
    let live: Bool
    /// Trail and glow; off under Reduce Motion. The dot and peaks still update.
    let showsMotion: Bool

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let range = model.configuration.ringRange
            func point(_ p: GMeterModel.Point) -> CGPoint {
                CGPoint(x: center.x + CGFloat(p.x / range) * radius, y: center.y - CGFloat(p.y / range) * radius)
            }
            func circle(_ r: CGFloat, at c: CGPoint = center) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }

            let markColor = live ? Theme.Colors.textDisabled : Theme.Colors.surfaceRaised
            // Crosshair, then the 0.5 g and 1.0 g rings.
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - radius, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - radius))
            cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            context.stroke(cross, with: .color(Theme.Colors.surfaceRaised), lineWidth: 1)
            context.stroke(circle(radius * 0.5), with: .color(markColor), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            context.stroke(circle(radius), with: .color(markColor), lineWidth: 1.5)

            guard live, let dot = model.dot else { return }

            // Peak markers: short ticks across each axis at the held maximum.
            for direction in GMeterModel.PeakDirection.allCases where model.peaks[direction] > 0.05 {
                let at = point(model.peakPosition(direction))
                let horizontal = direction == .left || direction == .right
                var tick = Path()
                if horizontal {
                    tick.move(to: CGPoint(x: at.x, y: at.y - 4))
                    tick.addLine(to: CGPoint(x: at.x, y: at.y + 4))
                } else {
                    tick.move(to: CGPoint(x: at.x - 4, y: at.y))
                    tick.addLine(to: CGPoint(x: at.x + 4, y: at.y))
                }
                context.stroke(tick, with: .color(Theme.Colors.signalYellow), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            if showsMotion {
                let window = Self.seconds(model.configuration.trailWindow)
                for sample in model.trail.dropLast() {
                    let fade = max(0, 1 - Self.seconds(sample.age) / window)
                    context.fill(
                        circle(2 + 2 * fade, at: point(sample.position)),
                        with: .color(Theme.Colors.accent.opacity(0.5 * fade))
                    )
                }
            }

            let dotCenter = point(dot)
            if showsMotion {
                var glow = context
                glow.addFilter(.shadow(color: Theme.Colors.accent.opacity(0.8), radius: 6))
                glow.fill(circle(6, at: dotCenter), with: .color(Theme.Colors.accent))
            } else {
                context.fill(circle(6, at: dotCenter), with: .color(Theme.Colors.accent))
            }
        }
        .accessibilityHidden(true)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
