import SwiftUI
import DesignSystem
import CompanionLink

/// How the phone shows data. Nothing here changes the controller's config,
/// which stays in Setup. Like iPhone Settings, the top level lists a few
/// categories; each opens its own page.
struct AppSettingsView: View {
    let model: AppModel
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
                SettingsSeparator()
                NavigationLink {
                    GaugesSettingsView(model: model)
                } label: {
                    SettingsRow(systemImage: "dial.medium", title: "Gauges", value: model.appConfig.rpmBand.settingsSummary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.gauges")
            }
        }
    }
}

/// The in-app RPM span and redline the shift lights, RPM bar and red zone
/// are drawn against. The error updates as you type, but edits apply only on
/// commit: leaving a field, Done, the Redline toggle, or leaving the page. An
/// invalid draft at commit leaves the last committed band live.
struct GaugesSettingsView: View {
    let model: AppModel
    @State private var draft: RPMBandDraft
    @FocusState private var focused: RPMBandDraft.Field?

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: RPMBandDraft(model.appConfig.rpmBand))
    }

    var body: some View {
        SettingsPage(eyebrow: "Settings // Gauges", title: "Gauges") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SettingsGroup(header: "RPM display") {
                    RPMEntryRow(title: "Fill start", text: $draft.fillFrom, field: .fillFrom, focused: $focused,
                                id: "settings.rpm.fillFrom")
                    SettingsSeparator()
                    RPMEntryRow(title: "Fill end", text: $draft.fillTo, field: .fillTo, focused: $focused,
                                id: "settings.rpm.fillTo")
                    SettingsSeparator()
                    Toggle(isOn: $draft.redlineOn.animation()) {
                        Text("Redline")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .tint(Theme.Colors.accent)
                    .settingsRowFrame()
                    .accessibilityIdentifier("settings.rpm.redlineEnabled")
                    if draft.redlineOn {
                        SettingsSeparator()
                        RPMEntryRow(title: "Redline at", text: $draft.redline, field: .redline, focused: $focused,
                                    id: "settings.rpm.redline")
                    }
                }
                if let problem = draft.problem {
                    Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.signalYellow)
                        .padding(.horizontal, Theme.Spacing.md)
                        .accessibilityIdentifier("settings.rpm.error")
                }
                Text("Shift lights fill from start to end; the RPM bar and numbers turn red at the redline. Up to \(SetupNumericEntry.formatted(RPMBand.maximumRPM)) rpm. Changes apply when you tap Done or leave a field, and only if every value is valid.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focused) { old, new in
            if old != nil, old != new { commit() }
        }
        .onChange(of: draft.redlineOn) { commit() }
        .onDisappear { commit(announce: false) }
    }

    private func commit(announce: Bool = true) {
        guard let problem = model.commitRPMBand(&draft), announce else { return }
        AccessibilityNotification.Announcement(problem.message).post()
    }
}

/// A titled whole-number RPM entry on one settings row.
private struct RPMEntryRow: View {
    var title: String
    @Binding var text: String
    var field: RPMBandDraft.Field
    var focused: FocusState<RPMBandDraft.Field?>.Binding
    var id: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityHidden(true)
            Spacer(minLength: Theme.Spacing.xs)
            TextField(title, text: $text)
                .font(Theme.Typography.value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.done)
                .focused(focused, equals: field)
                .onSubmit { focused.wrappedValue = nil }
                .frame(width: 96)
                .padding(Theme.Spacing.xs)
                .background(Theme.Colors.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(Theme.Colors.separator, lineWidth: 1))
                .accessibilityLabel("\(title), rpm")
                .accessibilityIdentifier(id)
            Text("rpm")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .settingsRowFrame()
        .onTapGesture { focused.wrappedValue = field }
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
        .toolbarBackground(.visible, for: .navigationBar)
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
                .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
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
    NavigationStack { AppSettingsView(model: AppModel(session: DemoScenario.connected.makeSession())) }
}
