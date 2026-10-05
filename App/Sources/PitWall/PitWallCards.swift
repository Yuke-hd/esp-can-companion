import SwiftUI
import DesignSystem
import CompanionLink

// MARK: - Controller strip

/// The red-edged strip under the title: firmware, profile and bus.
struct ControllerStrip: View {
    var firmware: String?
    var profile: String?
    var bus: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Card(edge: Theme.Colors.accent) {
            let fields = Group {
                field("Controller", firmware.map { "FW \($0)" } ?? "—", Theme.Colors.textPrimary)
                field("Profile", profile ?? "—", Theme.Colors.accentText)
                field("Bus", bus, Theme.Colors.signalTeal)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) { fields }
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) { fields }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controller")
    }

    private func field(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label).themeLabel()
            Text(value.uppercased())
                .font(Theme.Typography.headline)
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Live telemetry

/// Shift lights, RPM, gear, speed and the RPM bar.
struct TelemetryCard: View {
    var readout: PitWallReadout
    var framesPerSecond: Int
    var failure: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the readouts stack, so labels keep their width.
        let readouts = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.xs))
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("Live telemetry").themeLabel()
                    Spacer()
                    HStack(spacing: Theme.Spacing.xxs) {
                        Circle()
                            .fill(framesPerSecond > 0 ? Theme.Colors.signalTeal : Theme.Colors.textDisabled)
                            .frame(width: 6, height: 6)
                        Text("\(framesPerSecond) Hz")
                            .themeLabel(framesPerSecond > 0 ? Theme.Colors.signalTeal : Theme.Colors.textTertiary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(framesPerSecond > 0 ? "\(framesPerSecond) frames per second" : "No live signals")
                }

                ShiftLights(lit: readout.litShiftLights, firstRed: readout.firstRedShiftLight)

                readouts {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(readout.rpmText)
                            .font(Theme.Typography.readoutLarge)
                            .foregroundStyle(readout.rpm == nil ? Theme.Colors.textDisabled : Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("Engine rpm · \(readout.rpmFreshness.title)")
                            .themeLabel(readout.rpmFreshness.color)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(readout.rpmAccessibilityText)
                    Spacer(minLength: 0)
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        ReadoutTile(box: readout.gearBox, color: Theme.Colors.signalYellow)
                        ReadoutTile(box: readout.speedBox, color: Theme.Colors.textPrimary)
                    }
                }

                RPMBar(fraction: readout.rpmFraction, redline: readout.redlineFraction)

                if let failure {
                    Text(failure)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.signalYellow)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live telemetry")
    }
}

/// A small boxed readout such as gear or speed, with its freshness on screen.
private struct ReadoutTile: View {
    var box: ReadoutBox
    var color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ForEach(box.lines) { line in
                switch line.role {
                case .label:
                    Text(line.text).themeLabel()
                case .value:
                    Text(line.text)
                        .font(Theme.Typography.readoutMedium)
                        .foregroundStyle(box.isShown ? color : Theme.Colors.textDisabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                case .freshness:
                    Text(line.text)
                        .themeLabel(box.freshness.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(minWidth: 72)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.xs)
        .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.xs))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(box.accessibilityText)
    }
}

/// The row of round shift lights: green up to the redline, red past it.
struct ShiftLights: View {
    var lit: Int
    var firstRed: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<PitWallReadout.shiftLightCount, id: \.self) { index in
                let isRed = firstRed.map { index >= $0 } ?? false
                let color = isRed ? Theme.Colors.accent : Theme.Colors.signalGreen
                Circle()
                    .fill(index < lit ? color : Theme.Colors.surfaceRaised)
                    .overlay(Circle().strokeBorder(color.opacity(index < lit ? 0 : 0.25), lineWidth: 1))
                    .frame(maxWidth: 16)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shift lights, \(lit) of \(PitWallReadout.shiftLightCount) lit")
    }
}

/// A thin RPM bar from teal through yellow to red, with the redline marked.
struct RPMBar: View {
    var fraction: Double
    var redline: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.Colors.surfaceRaised)
                if let redline {
                    Rectangle()
                        .fill(Theme.Colors.accent.opacity(0.45))
                        .frame(width: width * (1 - redline))
                        .offset(x: width * redline)
                }
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Theme.Colors.signalTeal, Theme.Colors.signalYellow, Theme.Colors.accent],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * fraction)
                    }
                if fraction > 0 {
                    Rectangle()
                        .fill(Theme.Colors.textPrimary)
                        .frame(width: 2, height: 10)
                        .offset(x: max(width * fraction - 1, 0))
                }
            }
        }
        .frame(height: 6)
        .animation(.linear(duration: 0.1), value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Signal tiles

/// Brake, turn, hazard, doors, lock and wipers, each with its freshness.
struct SignalTileGrid: View {
    var tiles: [PitWallReadout.Tile]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
        )
        LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
            ForEach(tiles) { tile in
                SignalTileView(tile: tile)
            }
        }
    }
}

private struct SignalTileView: View {
    var tile: PitWallReadout.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack {
                Text(tile.title).themeLabel()
                Spacer(minLength: 0)
                Circle()
                    .fill(tile.freshness.color)
                    .frame(width: 6, height: 6)
            }
            Text((tile.value ?? "—").uppercased())
                .font(Theme.Typography.value)
                .foregroundStyle(tile.value == nil ? Theme.Colors.textDisabled : tile.tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(tile.freshness.title).themeLabel(tile.freshness.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityText)
    }
}

// MARK: - Output stack

/// The active config's outputs, highest priority first.
///
/// The controller does not report which outputs it is driving, so this
/// shows each output's kind rather than guessing live or idle.
struct OutputStackCard: View {
    var outputs: [ConfigSummary.Output]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Output stack").themeLabel()
                    Spacer()
                    Text("By priority").themeLabel(Theme.Colors.textTertiary)
                }
                .padding(.bottom, Theme.Spacing.xs)
                if outputs.isEmpty {
                    Text("This config drives no outputs.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.vertical, Theme.Spacing.xs)
                }
                ForEach(Array(outputs.enumerated()), id: \.element.id) { index, output in
                    Divider().overlay(Theme.Colors.separator)
                    row(index + 1, output)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Output stack")
    }

    private func row(_ position: Int, _ output: ConfigSummary.Output) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("\(position)")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(minWidth: 16, alignment: .leading)
            Rectangle()
                .fill(output.swatch.color)
                .frame(width: 3, height: 18)
            Text(output.title.uppercased())
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            Text("P\(output.priority)").themeLabel(Theme.Colors.textSecondary)
            Text(output.kindTitle)
                .themeLabel(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 2)
                .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.xs))
        }
        .padding(.vertical, Theme.Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position). \(output.accessibilityText)")
    }
}
