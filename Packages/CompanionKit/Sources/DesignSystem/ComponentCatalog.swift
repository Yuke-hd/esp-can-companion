import SwiftUI

/// Preview catalog of the core components on the app background.
/// Open this file in Xcode and use the canvas to review changes to the theme.
/// All values shown are synthetic.
public struct ComponentCatalog: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                section("Typography") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("PIT WALL").font(Theme.Typography.display)
                        Text("4,820").font(Theme.Typography.readoutLarge)
                        Text("RELEASED").font(Theme.Typography.value)
                        Text("RPM FILL").font(Theme.Typography.headline)
                        Text("Body text for descriptions.").font(Theme.Typography.body)
                        Text("Engine RPM · unverified").themeLabel(Theme.Colors.signalYellow)
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                }

                section("Signal colors") {
                    HStack(spacing: Theme.Spacing.xs) {
                        swatch(Theme.Colors.accent)
                        swatch(Theme.Colors.signalTeal)
                        swatch(Theme.Colors.signalYellow)
                        swatch(Theme.Colors.signalGreen)
                        swatch(Theme.Colors.signalBlue)
                        swatch(Theme.Colors.signalPurple)
                    }
                }

                section("Status pill") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            StatusPill("Linked", status: .live)
                            StatusPill("3 changes", status: .pending)
                            StatusPill("Editing", status: .editing)
                        }
                        HStack(spacing: Theme.Spacing.xs) {
                            StatusPill("Idle", status: .neutral)
                            StatusPill("Fault", status: .alert)
                        }
                    }
                }

                section("Card") {
                    VStack(spacing: Theme.Spacing.sm) {
                        Card(edge: Theme.Colors.accent) {
                            HStack(alignment: .top) {
                                field("Controller", "CAN485 · FW 0.4", Theme.Colors.textPrimary)
                                Spacer()
                                field("Profile", "TRACK", Theme.Colors.accent)
                                Spacer()
                                field("Bus", "LISTEN-ONLY", Theme.Colors.signalTeal)
                            }
                        }
                        HStack(spacing: Theme.Spacing.sm) {
                            Card {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                    Text("Brake").themeLabel()
                                    Text("RELEASED").font(Theme.Typography.value)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text("Unverified").themeLabel(Theme.Colors.signalYellow)
                                }
                            }
                            Card {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                    Text("Wipers").themeLabel()
                                    Text("—").font(Theme.Typography.value)
                                        .foregroundStyle(Theme.Colors.textDisabled)
                                    Text("Stale").themeLabel(Theme.Colors.textDisabled)
                                }
                            }
                        }
                    }
                }

                section("Buttons") {
                    VStack(spacing: Theme.Spacing.sm) {
                        Button("Send to car") {}.buttonStyle(.primary)
                        HStack(spacing: Theme.Spacing.sm) {
                            Button("Preview") {}.buttonStyle(.secondary)
                            Button("Send") {}.buttonStyle(.primary)
                        }
                        Button("Disabled") {}.buttonStyle(.primary).disabled(true)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).themeLabel()
            content()
        }
    }

    private func field(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label).themeLabel()
            Text(value).font(Theme.Typography.headline).foregroundStyle(color)
        }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.xs)
            .fill(color)
            .frame(width: 36, height: 36)
    }
}

#Preview("Component catalog") {
    ComponentCatalog()
}
