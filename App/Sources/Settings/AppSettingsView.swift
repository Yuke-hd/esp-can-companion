import SwiftUI
import DesignSystem

/// How the phone shows data. Nothing here changes the controller's config,
/// which stays in Setup. Like iPhone Settings, the top level lists a few
/// categories; each opens its own page.
struct AppSettingsView: View {
    @AppStorage(DriveStyle.storageKey) private var driveStyle: DriveStyle = .motorsport

    var body: some View {
        SettingsPage(eyebrow: "Garage // App", title: "Settings") {
            SettingsGroup {
                NavigationLink {
                    DriveSettingsView()
                } label: {
                    SettingsRow(systemImage: "gauge.with.dots.needle.67percent", title: "Drive", value: driveStyle.title)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.drive")
            }
        }
    }
}

/// The Drive screen's style. The Drive cycle button switches between the same styles.
struct DriveSettingsView: View {
    @AppStorage(DriveStyle.storageKey) private var driveStyle: DriveStyle = .motorsport

    var body: some View {
        SettingsPage(eyebrow: "Settings // Drive", title: "Drive") {
            SettingsGroup(header: "Style", footer: "The Drive screen's style button switches between the same styles.") {
                ForEach(DriveStyle.allCases, id: \.self) { style in
                    if style != DriveStyle.allCases.first { SettingsSeparator() }
                    Button { driveStyle = style } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(style.title)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer(minLength: Theme.Spacing.xs)
                            Image(systemName: "checkmark")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.signalYellow)
                                .opacity(style == driveStyle ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .settingsRowFrame()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Drive style, \(style.title)")
                    .accessibilityAddTraits(style == driveStyle ? .isSelected : [])
                    .accessibilityIdentifier("settings.driveStyle.\(style.rawValue)")
                }
            }
        }
    }
}

// MARK: - Building blocks

/// A themed settings page: the screen header, then grouped rows.
private struct SettingsPage<Content: View>: View {
    var eyebrow: String
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ScreenHeader(eyebrow: eyebrow, title: title)
                content
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Theme.Colors.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Rows on one surface, with an optional label above and note below, like an
/// inset grouped list.
private struct SettingsGroup<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let header {
                Text(header)
                    .themeLabel(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            if let footer {
                Text(footer)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
}

/// A row that opens a sub-page: icon, title, the current value and a chevron.
private struct SettingsRow: View {
    var systemImage: String
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.xs)
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Image(systemName: "chevron.right")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .settingsRowFrame()
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.md)
    }
}

private extension View {
    func settingsRowFrame() -> some View {
        frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { AppSettingsView() }
}
