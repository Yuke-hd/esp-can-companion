import SwiftUI
import DesignSystem

/// The content regions that the Drive styles can fill independently.
///
/// The container owns placement and safe-area handling; a style can replace
/// any slot without changing navigation or lifecycle.
struct DriveScreenSlots {
    let backdrop: AnyView
    let shiftLights: AnyView
    let leftIndicator: AnyView
    let rightIndicator: AnyView
    let rpm: AnyView
    let speed: AnyView
    let gear: AnyView
    let sideMeters: AnyView
    let auxiliary: AnyView
    let link: AnyView

    init<Backdrop: View, ShiftLights: View, LeftIndicator: View, RightIndicator: View, RPM: View, Speed: View, Gear: View, SideMeters: View, Auxiliary: View, Link: View>(
        @ViewBuilder backdrop: () -> Backdrop = { Color.clear },
        @ViewBuilder shiftLights: () -> ShiftLights,
        @ViewBuilder leftIndicator: () -> LeftIndicator,
        @ViewBuilder rightIndicator: () -> RightIndicator,
        @ViewBuilder rpm: () -> RPM,
        @ViewBuilder speed: () -> Speed,
        @ViewBuilder gear: () -> Gear,
        @ViewBuilder sideMeters: () -> SideMeters,
        @ViewBuilder auxiliary: () -> Auxiliary,
        @ViewBuilder link: () -> Link
    ) {
        self.backdrop = AnyView(backdrop())
        self.shiftLights = AnyView(shiftLights())
        self.leftIndicator = AnyView(leftIndicator())
        self.rightIndicator = AnyView(rightIndicator())
        self.rpm = AnyView(rpm())
        self.speed = AnyView(speed())
        self.gear = AnyView(gear())
        self.sideMeters = AnyView(sideMeters())
        self.auxiliary = AnyView(auxiliary())
        self.link = AnyView(link())
    }

    static var placeholder: DriveScreenSlots {
        DriveScreenSlots(
            shiftLights: { DriveSlotPlaceholder(label: "SHIFT LIGHTS", value: "--") },
            leftIndicator: { DriveSlotPlaceholder(label: "LEFT", value: "--") },
            rightIndicator: { DriveSlotPlaceholder(label: "RIGHT", value: "--") },
            rpm: { DriveSlotPlaceholder(label: "RPM", value: "--") },
            speed: { DriveSlotPlaceholder(label: "KM/H", value: "--") },
            gear: { DriveSlotPlaceholder(label: "GEAR", value: "--") },
            sideMeters: { Color.clear },
            auxiliary: { DriveSlotPlaceholder(label: "AUX", value: "--") },
            link: { DriveSlotPlaceholder(label: "LINK", value: "--") }
        )
    }
}

/// Sizes the Drive layout derives from the screen, shared with the slots so
/// type and gauges scale together on small and large phones.
struct DriveMetrics: Equatable {
    /// Side columns (RPM, speed) width.
    var sideColumnWidth: CGFloat = 220
    /// Height available to the centre gauges.
    var gaugeHeight: CGFloat = 260
    /// Large numeral size for RPM and speed.
    var numeralSize: CGFloat = 72

    static func make(contentSize size: CGSize) -> DriveMetrics {
        let sideColumnWidth = (size.width * 0.22).rounded()
        // Shift lights, their gap and the link line take ~70 points.
        let gaugeHeight = max(160, size.height - 70)
        let numeralSize = min(76, max(52, size.height * 0.19)).rounded()
        return DriveMetrics(sideColumnWidth: sideColumnWidth, gaugeHeight: gaugeHeight, numeralSize: numeralSize)
    }
}

private struct DriveMetricsKey: EnvironmentKey {
    static let defaultValue = DriveMetrics()
}

extension EnvironmentValues {
    var driveMetrics: DriveMetrics {
        get { self[DriveMetricsKey.self] }
        set { self[DriveMetricsKey.self] = newValue }
    }
}

/// A landscape-only shell for the passive Drive display.
struct DriveScreen: View {
    let slots: DriveScreenSlots
    let onExit: () -> Void

    init(slots: DriveScreenSlots = .placeholder, onExit: @escaping () -> Void = {}) {
        self.slots = slots
        self.onExit = onExit
    }

    var body: some View {
        // Read the insets from a reader that respects the safe area, then lay
        // the content out across the whole screen. The horizontal inset in
        // landscape is mostly empty glass beside the Dynamic Island, so only
        // keep enough of it to clear the island itself.
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let fullWidth = proxy.size.width + insets.leading + insets.trailing
            let fullHeight = proxy.size.height + insets.top + insets.bottom
            let sideInset = max(insets.leading, insets.trailing)
            let horizontalMargin = max(Theme.Spacing.md, sideInset - Theme.Spacing.xs)
            let topMargin = max(Theme.Spacing.sm, insets.top)
            // The home indicator floats over the bottom edge; the link line
            // may sit beside it, so keep only part of that inset.
            let bottomMargin = max(Theme.Spacing.xs, insets.bottom * 0.5)
            let contentSize = CGSize(
                width: max(0, fullWidth - horizontalMargin * 2),
                height: max(0, fullHeight - topMargin - bottomMargin)
            )
            let metrics = DriveMetrics.make(contentSize: contentSize)

            content(metrics: metrics, contentWidth: contentSize.width)
                .frame(width: contentSize.width, height: contentSize.height)
                .padding(.horizontal, horizontalMargin)
                .padding(.top, topMargin)
                .padding(.bottom, bottomMargin)
                .frame(width: fullWidth, height: fullHeight)
                .offset(x: -insets.leading, y: -insets.top)
                .environment(\.driveMetrics, metrics)
        }
        // The backdrop spans the whole screen, under the island and the
        // home indicator, for effects such as the turn-signal glow.
        .background(slots.backdrop.ignoresSafeArea().allowsHitTesting(false))
        .background(Theme.Colors.background.ignoresSafeArea())
        .statusBarHidden(true)
    }

    private func content(metrics: DriveMetrics, contentWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                slots.shiftLights
                    .frame(width: min(600, contentWidth * 0.72), height: 26)
                    .frame(maxWidth: .infinity)

                exitButton
            }
            .frame(height: 30)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    slots.leftIndicator
                    slots.rpm
                    Spacer(minLength: 0)
                }
                .frame(width: metrics.sideColumnWidth, alignment: .leading)

                VStack(spacing: Theme.Spacing.xs) {
                    // Keep the side gauges close around the gear, as the
                    // draft's brackets are, rather than at the column edges.
                    ZStack {
                        slots.sideMeters
                        slots.gear
                    }
                    .frame(maxWidth: metrics.gaugeHeight * 1.45, maxHeight: .infinity)
                    .frame(maxWidth: .infinity)

                    slots.link
                        .frame(height: 16)
                }
                .padding(.horizontal, Theme.Spacing.sm)

                VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                    slots.rightIndicator
                    slots.speed
                    Spacer(minLength: 0)
                    slots.auxiliary
                }
                .frame(width: metrics.sideColumnWidth, alignment: .trailing)
            }
            .padding(.top, Theme.Spacing.md)
            .frame(maxHeight: .infinity)
        }
    }

    private var exitButton: some View {
        Button(action: onExit) {
            Label("Exit Drive", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.surfaceRaised, in: Circle())
                .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exit Drive")
        .accessibilityIdentifier("drive.exit")
    }
}

private struct DriveSlotPlaceholder: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label).themeLabel()
            Text(value)
                .font(Theme.Typography.value)
                .foregroundStyle(Theme.Colors.textDisabled)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

struct DriveScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DriveScreen()
                .preferredColorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone 15 Pro"))
                .previewInterfaceOrientation(.landscapeLeft)
                .previewDisplayName("Dynamic Island")

            DriveScreen()
                .preferredColorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
                .previewInterfaceOrientation(.landscapeLeft)
                .previewDisplayName("Home button")
        }
    }
}
