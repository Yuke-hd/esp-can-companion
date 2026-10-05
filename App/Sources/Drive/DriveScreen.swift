import SwiftUI
import DesignSystem

/// The content regions that the Drive styles can fill independently.
///
/// The container owns placement and safe-area handling; the style work in a
/// later issue can replace any slot without changing navigation or lifecycle.
struct DriveScreenSlots {
    let gear: AnyView
    let rpm: AnyView
    let speed: AnyView
    let sideMeters: AnyView
    let turnIndicators: AnyView
    let warnings: AnyView
    let statusStrip: AnyView

    init<Gear: View, RPM: View, Speed: View, SideMeters: View, TurnIndicators: View, Warnings: View, StatusStrip: View>(
        @ViewBuilder gear: () -> Gear,
        @ViewBuilder rpm: () -> RPM,
        @ViewBuilder speed: () -> Speed,
        @ViewBuilder sideMeters: () -> SideMeters,
        @ViewBuilder turnIndicators: () -> TurnIndicators,
        @ViewBuilder warnings: () -> Warnings,
        @ViewBuilder statusStrip: () -> StatusStrip
    ) {
        self.gear = AnyView(gear())
        self.rpm = AnyView(rpm())
        self.speed = AnyView(speed())
        self.sideMeters = AnyView(sideMeters())
        self.turnIndicators = AnyView(turnIndicators())
        self.warnings = AnyView(warnings())
        self.statusStrip = AnyView(statusStrip())
    }

    static var placeholder: DriveScreenSlots {
        DriveScreenSlots(
            gear: { DriveSlotPlaceholder(label: "GEAR", value: "--") },
            rpm: { DriveSlotPlaceholder(label: "RPM", value: "--") },
            speed: { DriveSlotPlaceholder(label: "KM/H", value: "--") },
            sideMeters: { DriveSlotPlaceholder(label: "SIDE METERS", value: "--") },
            turnIndicators: { DriveSlotPlaceholder(label: "TURN INDICATORS", value: "--") },
            warnings: { DriveSlotPlaceholder(label: "WARNINGS", value: "NONE") },
            statusStrip: { DriveSlotPlaceholder(label: "STATUS", value: "DRIVE PLACEHOLDER") }
        )
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
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Theme.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        slots.turnIndicators
                            .frame(maxWidth: .infinity, alignment: .leading)
                        slots.warnings
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(minHeight: 32)

                    HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            slots.rpm
                            slots.sideMeters
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        slots.gear
                            .frame(maxWidth: .infinity)

                        slots.speed
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    slots.statusStrip
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, max(Theme.Spacing.sm, proxy.safeAreaInsets.top))
                .padding(.leading, max(Theme.Spacing.md, proxy.safeAreaInsets.leading))
                .padding(.trailing, max(Theme.Spacing.md, proxy.safeAreaInsets.trailing))
                .padding(.bottom, max(Theme.Spacing.sm, proxy.safeAreaInsets.bottom))

                Button(action: onExit) {
                    Label("Exit Drive", systemImage: "rectangle.portrait.and.arrow.right")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(Theme.Spacing.xs)
                        .background(Theme.Colors.surface.opacity(0.9), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit Drive")
                .accessibilityIdentifier("drive.exit")
                .padding(.top, max(Theme.Spacing.xs, proxy.safeAreaInsets.top))
                .padding(.trailing, max(Theme.Spacing.sm, proxy.safeAreaInsets.trailing))
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .ignoresSafeArea()
        .statusBarHidden(true)
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
