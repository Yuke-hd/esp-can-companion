import SwiftUI

/// Preview catalog of the core components on the app background.
/// Open this file in Xcode and use the canvas to review changes to the theme.
public struct ComponentCatalog: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                section("Typography") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Large title").font(Theme.Typography.largeTitle)
                        Text("Title").font(Theme.Typography.title)
                        Text("Headline").font(Theme.Typography.headline)
                        Text("Body text for descriptions.").font(Theme.Typography.body)
                        Text("Caption").font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("12.6 V").font(Theme.Typography.readout)
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                }

                section("Status pill") {
                    HStack(spacing: Theme.Spacing.xs) {
                        StatusPill("Idle", status: .neutral)
                        StatusPill("Connected", status: .success)
                        StatusPill("Pairing", status: .warning)
                        StatusPill("Error", status: .danger)
                    }
                }

                section("Card") {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack {
                                Text("Controller").font(Theme.Typography.headline)
                                Spacer()
                                StatusPill("Connected", status: .success)
                            }
                            Text("Synthetic sample data").font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }

                section("Primary button") {
                    VStack(spacing: Theme.Spacing.sm) {
                        Button("Connect") {}.buttonStyle(.primary)
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
            Text(title.uppercased())
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            content()
        }
    }
}

#Preview("Component catalog") {
    ComponentCatalog()
}
