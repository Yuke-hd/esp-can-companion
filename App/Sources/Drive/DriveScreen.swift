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

    /// Share of the width for each of the RPM and speed columns: wide enough
    /// for a five-digit RPM at the largest numeral size on an SE.
    static let sideColumnShare: CGFloat = 0.22
    /// Height taken above and below the gauges by the shift lights, their gap
    /// and the link line.
    static let chromeHeight: CGFloat = 70
    /// Below this the gauges become unreadable; content scales down instead.
    static let minimumGaugeHeight: CGFloat = 160
    /// The centre cluster's widest aspect ratio relative to the gauge height,
    /// so side gauges stay hugging the gear rather than drifting to the edges.
    static let centreClusterAspect: CGFloat = 1.45

    static func make(contentSize size: CGSize) -> DriveMetrics {
        let sideColumnWidth = (size.width * sideColumnShare).rounded()
        let gaugeHeight = max(minimumGaugeHeight, size.height - chromeHeight)
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
    /// How a style fills the screen: the column slots, or one view of its
    /// own with the controls floating over it.
    private enum Layout {
        case slots(DriveScreenSlots)
        case fill(backdrop: AnyView, content: AnyView)
    }

    private let layout: Layout
    let onExit: () -> Void
    /// Switches to the next Drive style, or nil to hide the control.
    var onSwitchStyle: (() -> Void)?
    var isSoundEnabled = false
    var onSoundSettings: (() -> Void)?

    init(slots: DriveScreenSlots = .placeholder, onExit: @escaping () -> Void = {}, onSwitchStyle: (() -> Void)? = nil, isSoundEnabled: Bool = false, onSoundSettings: (() -> Void)? = nil) {
        self.layout = .slots(slots)
        self.onExit = onExit
        self.onSwitchStyle = onSwitchStyle
        self.isSoundEnabled = isSoundEnabled
        self.onSoundSettings = onSoundSettings
    }

    /// A style that draws its whole layout itself, across the screen's full
    /// width, under the controls.
    init<Backdrop: View, Content: View>(
        onExit: @escaping () -> Void,
        onSwitchStyle: (() -> Void)? = nil,
        isSoundEnabled: Bool = false,
        onSoundSettings: (() -> Void)? = nil,
        @ViewBuilder backdrop: () -> Backdrop = { Color.clear },
        @ViewBuilder content: () -> Content
    ) {
        self.layout = .fill(backdrop: AnyView(backdrop()), content: AnyView(content()))
        self.onExit = onExit
        self.onSwitchStyle = onSwitchStyle
        self.isSoundEnabled = isSoundEnabled
        self.onSoundSettings = onSoundSettings
    }

    private var backdrop: AnyView {
        switch layout {
        case .slots(let slots): slots.backdrop
        case .fill(let backdrop, _): backdrop
        }
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

            content(metrics: metrics, contentWidth: contentSize.width, horizontalMargin: horizontalMargin)
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
        .background(backdrop.ignoresSafeArea().allowsHitTesting(false))
        .background(Theme.Colors.background.ignoresSafeArea())
        .statusBarHidden(true)
    }

    @ViewBuilder private func content(metrics: DriveMetrics, contentWidth: CGFloat, horizontalMargin: CGFloat) -> some View {
        switch layout {
        case .slots(let slots):
            columns(slots, metrics: metrics, contentWidth: contentWidth)
        case .fill(_, let content):
            // A style that draws itself runs edge to edge, under the island,
            // with the controls floating over its top corner.
            ZStack(alignment: .topTrailing) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, -horizontalMargin)
                controls
            }
        }
    }

    private func columns(_ slots: DriveScreenSlots, metrics: DriveMetrics, contentWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                slots.shiftLights
                    .frame(width: min(600, contentWidth * 0.72, max(0, contentWidth - controlsWidth * 2)), height: 26)
                    .frame(maxWidth: .infinity)

                controls
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
                    .frame(maxWidth: metrics.gaugeHeight * DriveMetrics.centreClusterAspect, maxHeight: .infinity)
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

    private var controls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let onSoundSettings {
                controlButton("Engine sound settings", systemImage: isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash",
                              identifier: "drive.sound", action: onSoundSettings)
                    .accessibilityValue(isSoundEnabled ? "On" : "Off")
            }
            if let onSwitchStyle {
                controlButton("Change Drive style", systemImage: "gauge.with.dots.needle.67percent", identifier: "drive.style", action: onSwitchStyle)
            }
            controlButton("Exit Drive", systemImage: "xmark", identifier: "drive.exit", action: onExit)
        }
    }

    private var controlsWidth: CGFloat {
        let count = 1 + (onSwitchStyle == nil ? 0 : 1) + (onSoundSettings == nil ? 0 : 1)
        return CGFloat(count) * 30 + CGFloat(count - 1) * Theme.Spacing.sm
    }

    private func controlButton(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.surfaceRaised, in: Circle())
                .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
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
