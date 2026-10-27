import SwiftUI
import DesignSystem
import CompanionLink

/// How the phone shows data. Nothing here changes the controller's config,
/// which stays in Setup. Like iPhone Settings, the top level lists a few
/// categories; each opens its own page.
struct AppSettingsView: View {
    let model: AppModel
    @AppStorage(DriveStyle.storageKey) private var driveStyle: DriveStyle = .motorsport
    @State private var confirmingReset = false

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
            SettingsGroup(footer: "Restores the Drive style, RPM display and brake scale. The controller's config is not changed.") {
                Button(role: .destructive) { confirmingReset = true } label: {
                    Text("Reset to defaults")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.accentText)
                        .settingsRowFrame()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.reset")
            }
            .confirmationDialog("Reset app settings to defaults?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset to Defaults", role: .destructive) {
                    model.resetAppSettings()
                    driveStyle = .motorsport
                }
                .accessibilityIdentifier("settings.reset.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Drive style, RPM display and brake scale return to their defaults.")
            }
        }
    }
}

/// The in-app RPM span and redline the shift lights, RPM bar and red zone
/// are drawn against, and the brake pressure scale the Drive brake bar fills
/// against. Errors update as you type, but edits apply only on commit:
/// leaving a field, Done, the Redline toggle, or leaving the page. An invalid
/// draft at commit leaves the last committed value live.
struct GaugesSettingsView: View {
    enum Field: Hashable {
        case rpm(RPMBandDraft.Field)
        case brakeScale
    }

    let model: AppModel
    @State private var draft: RPMBandDraft
    @State private var brakeDraft: BrakeScaleDraft
    @FocusState private var focused: Field?

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: RPMBandDraft(model.appConfig.rpmBand))
        _brakeDraft = State(initialValue: BrakeScaleDraft(model.appConfig.brakePressureBarScale))
    }

    var body: some View {
        SettingsPage(eyebrow: "Settings // Gauges", title: "Gauges") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SettingsGroup(header: "RPM display") {
                    NumberEntryRow(title: "Fill start", unit: "rpm", text: $draft.fillFrom, field: .rpm(.fillFrom),
                                   focused: $focused, id: "settings.rpm.fillFrom")
                    SettingsSeparator()
                    NumberEntryRow(title: "Fill end", unit: "rpm", text: $draft.fillTo, field: .rpm(.fillTo),
                                   focused: $focused, id: "settings.rpm.fillTo")
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
                        NumberEntryRow(title: "Redline at", unit: "rpm", text: $draft.redline, field: .rpm(.redline),
                                       focused: $focused, id: "settings.rpm.redline")
                    }
                }
                if let problem = draft.problem {
                    FieldError(message: problem.message, id: "settings.rpm.error")
                }
                Text("Shift lights fill from start to end; the RPM bar and numbers turn red at the redline. Up to \(SetupNumericEntry.formatted(RPMBand.maximumRPM)) rpm. Changes apply when you tap Done or leave a field, and only if every value is valid.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SettingsGroup(header: "Brake display") {
                    NumberEntryRow(title: "Pressure scale", unit: "bar", text: $brakeDraft.text, field: .brakeScale,
                                   focused: $focused, id: "settings.brake.scale",
                                   accessibilityTitle: "Brake pressure scale")
                }
                if let problem = brakeDraft.problem {
                    FieldError(message: problem.message, id: "settings.brake.error")
                }
                Text("Drive's brake bar is full at this pressure. A display scale only, \(SetupNumericEntry.formatted(AppConfig.brakePressureBarScaleRange.lowerBound)) to \(SetupNumericEntry.formatted(AppConfig.brakePressureBarScaleRange.upperBound)) bar.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focused) { old, new in
            if let old, old != new { commit(old) }
        }
        .onChange(of: draft.redlineOn) { commitRPM() }
        // Values committed elsewhere, such as Reset to defaults, replace the
        // drafts unless a field is being edited.
        .onAppear { resyncDrafts(rpm: true, brake: true) }
        .onChange(of: model.appConfig) { old, new in
            guard focused == nil else { return }
            resyncDrafts(rpm: old.rpmBand != new.rpmBand,
                         brake: old.brakePressureBarScale != new.brakePressureBarScale)
        }
        .onDisappear {
            commitRPM(announce: false)
            commitBrake(announce: false)
        }
    }

    private func commit(_ field: Field) {
        switch field {
        case .rpm: commitRPM()
        case .brakeScale: commitBrake()
        }
    }

    private func commitRPM(announce: Bool = true) {
        guard let problem = model.commitRPMBand(&draft), announce else { return }
        AccessibilityNotification.Announcement(problem.message).post()
    }

    private func commitBrake(announce: Bool = true) {
        guard let problem = model.commitBrakeScale(&brakeDraft), announce else { return }
        AccessibilityNotification.Announcement(problem.message).post()
    }

    /// Replaces a draft that does not already hold the committed value.
    private func resyncDrafts(rpm: Bool, brake: Bool) {
        let config = model.appConfig
        if rpm, (try? draft.result.get()) != config.rpmBand { draft = RPMBandDraft(config.rpmBand) }
        if brake, (try? brakeDraft.result.get()) != config.brakePressureBarScale {
            brakeDraft = BrakeScaleDraft(config.brakePressureBarScale)
        }
    }
}

/// An inline validation message under a settings group.
private struct FieldError: View {
    var message: String
    var id: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.signalYellow)
            .padding(.horizontal, Theme.Spacing.md)
            .accessibilityIdentifier(id)
    }
}

/// A titled whole-number entry with its unit on one settings row.
private struct NumberEntryRow: View {
    var title: String
    var unit: String
    @Binding var text: String
    var field: GaugesSettingsView.Field
    var focused: FocusState<GaugesSettingsView.Field?>.Binding
    var id: String
    /// The VoiceOver name when the visible title relies on its group header.
    var accessibilityTitle: String?

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
                .accessibilityLabel("\(accessibilityTitle ?? title), \(unit)")
                .accessibilityIdentifier(id)
            Text(unit)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(minWidth: 28, alignment: .leading)
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
