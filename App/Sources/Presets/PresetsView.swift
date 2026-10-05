import SwiftUI
import DesignSystem
import PresetSync
import CompanionProtocol

/// The Setup route: choose a preset, edit a complete draft, then send it.
struct PresetsView: View {
    @State private var model: PresetSyncModel
    @State private var selection: SetupSelection
    @State private var replacementPreset: Preset?
    let isConnected: Bool
    let isActiveConfigCurrent: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: PresetSyncModel, selection: SetupSelection? = nil, isConnected: Bool = true,
         isActiveConfigCurrent: Bool = true) {
        _model = State(initialValue: model)
        _selection = State(initialValue: selection ?? SetupSelection())
        self.isConnected = isConnected
        self.isActiveConfigCurrent = isActiveConfigCurrent
    }

    init(link: PresetSyncLink, onChange: (@MainActor () -> Void)? = nil) {
        let model = PresetSyncModel(presets: (try? PresetCatalog.bundled()) ?? [], link: link)
        model.onChange = onChange
        self.init(model: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    presetPicker
                    PresetActiveConfigCard(model: model, isConnected: isConnected, isActiveConfigCurrent: isActiveConfigCurrent)
                    if let preset = selection.preset {
                        SetupTweaksView(selection: selection)
                            .id(selection.draftRevision)
                            .disabled(model.phase != .idle)
                        RuleEditorView(config: configBinding)
                            .disabled(model.phase != .idle)
                        draftReset
                        DisclosureGroup("What this setup does") {
                            PresetActionList(preset: preset).padding(.top, Theme.Spacing.sm)
                        }
                        .font(Theme.Typography.headline)
                        .tint(Theme.Colors.textPrimary)
                    }
                    factorySection
                }
                .padding(Theme.Spacing.md)
            }
            .refreshable { if isConnected { await model.refresh() } }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sendFooter
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: isConnected) {
            if isConnected { await model.refresh() }
            chooseInitialPreset()
        }
        .presetSyncSheet(model: model) { _ in true }
        .alert("Discard draft changes?", isPresented: replacingPreset, presenting: replacementPreset) { preset in
            Button("Discard changes", role: .destructive) {
                selection.select(preset)
                replacementPreset = nil
            }
            Button("Keep editing", role: .cancel) { replacementPreset = nil }
        } message: { _ in
            Text("Switching presets replaces the changes you haven't sent to the car.")
        }
    }

    private var header: some View {
        ScreenHeader(eyebrow: "SETUP SHEET // PRESETS", title: "Setup") {
            selectionPill
        }
    }

    private var selectionPill: some View {
        StatusPill(selection.hasInputErrors ? "Check values" : selectionStatus == .pending ? pendingTitle : "On car",
                   status: selection.hasInputErrors ? .alert : selectionStatus == .pending ? .pending : .live)
            .opacity(selectionStatus == .none ? 0 : 1)
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if model.presets.isEmpty {
                Text("No presets are bundled with this build.")
                    .font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) { presetButtons }
                VStack(spacing: Theme.Spacing.xs) { presetButtons }
            }
        }
    }

    private var presetButtons: some View {
        ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
            Button { choosePreset(preset) } label: {
                SetupPresetTile(preset: preset, index: index,
                                selected: selection.basePreset?.id == preset.id,
                                onCar: isConnected && isActiveConfigCurrent && model.refreshError == nil && model.active?.presetID == preset.id)
            }
            .buttonStyle(.plain)
            .disabled(model.phase.isBusy)
            .accessibilityAddTraits(selection.basePreset?.id == preset.id ? .isSelected : [])
            .accessibilityIdentifier("setup.preset.\(preset.id)")
        }
    }

    private var factorySection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("FACTORY CONFIG").font(Theme.Typography.headline)
                Text("Restore the controller's original light configuration. You'll confirm before the saved preset is cleared.")
                    .font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                Button("Revert to factory") { model.requestRevert() }
                    .buttonStyle(.secondary)
                    .disabled(!isConnected || model.phase != .idle)
                    .accessibilityIdentifier("setup.factory")
            }
        }
    }

    private var sendFooter: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(footerStatus).themeLabel(footerColor)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) { validationLabel; sendButton }
            } else {
                HStack(spacing: Theme.Spacing.md) {
                    validationLabel.frame(maxWidth: .infinity, alignment: .leading)
                    sendButton.frame(width: 160)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.background)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.separator).frame(height: 1) }
    }

    private var validationLabel: some View {
        Group {
            if let issue = selection.rpmIssues.first {
                RPMValidationMessage(message: issue.summary, id: "setup.validation")
            } else {
                Text("CONTROLLER VALIDATES ON SEND").themeLabel().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sendButton: some View {
        Button("Send to car") {
            guard selection.canSend(isConnected: isConnected, phase: model.phase), let preset = selection.preset else { return }
            model.requestPush(preset)
        }
        .buttonStyle(.primary)
        .disabled(!selection.canSend(isConnected: isConnected, phase: model.phase))
        .accessibilityIdentifier("setup.send")
    }

    private var selectionStatus: SetupSelection.Status {
        selection.status(active: isConnected && isActiveConfigCurrent && model.refreshError == nil ? model.active : nil)
    }

    private var footerColor: Color {
        if selection.hasInputErrors { return Theme.Colors.signalYellow }
        if !isConnected { return Theme.Colors.textSecondary }
        return selectionStatus == .onCar ? Theme.Colors.signalTeal : Theme.Colors.signalYellow
    }

    private var footerStatus: String {
        if !selection.rpmIssues.isEmpty { return "CHECK RPM SETTINGS BEFORE SENDING" }
        if selection.hasInputErrors { return "CHECK NUMERIC FIELDS BEFORE SENDING" }
        if !isConnected { return "CONNECT TO SEND A PRESET" }
        if selectionStatus == .none { return "CHOOSE A PRESET" }
        if selectionStatus == .onCar { return selection.isModified ? "DRAFT SETUP · ON CAR" : "SELECTED PRESET · ON CAR" }
        if selection.isModified { return "\(selection.changeCount) CHANGES · NOT ON CAR" }
        return "SELECTED PRESET · NOT CONFIRMED ON CAR"
    }

    private var pendingTitle: String {
        selection.isModified ? "\(selection.changeCount) changes" : "Preset pending"
    }

    private var configBinding: Binding<ControllerConfig> {
        Binding(get: { selection.editableConfig ?? ControllerConfig() }, set: { selection.updateConfig($0) })
    }

    private var replacingPreset: Binding<Bool> {
        Binding(get: { replacementPreset != nil }, set: { if !$0 { replacementPreset = nil } })
    }

    @ViewBuilder
    private var draftReset: some View {
        if selection.isModified || selection.hasInputErrors {
            Button("Reset tweaks to bundled preset") { selection.resetTweaks() }
                .buttonStyle(.secondary)
                .disabled(model.phase != .idle)
                .accessibilityIdentifier("setup.reset")
        }
    }

    private func choosePreset(_ preset: Preset) {
        if selection.basePreset?.id != preset.id && (selection.hasInputErrors || selection.isModified && selectionStatus == .pending) {
            replacementPreset = preset
            return
        }
        selection.select(preset)
    }

    private func chooseInitialPreset() {
        guard selection.preset == nil else { return }
        let active = model.presets.first { $0.id == model.active?.presetID }
        if let initial = active ?? model.presets.first { selection.select(initial) }
    }
}

private struct SetupPresetTile: View {
    let preset: Preset
    let index: Int
    let selected: Bool
    let onCar: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(String(preset.name.prefix(1)).uppercased())
                .font(Theme.Typography.value.italic())
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(compoundColor, lineWidth: 5))
                .accessibilityHidden(true)
            Text(preset.name.uppercased())
                .font(Theme.Typography.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(onCar ? "ON CAR" : selected ? "SELECTED" : "BUNDLED")
                .themeLabel(onCar ? Theme.Colors.accentText : selected ? Theme.Colors.signalYellow : Theme.Colors.textSecondary)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(minWidth: 84, maxWidth: .infinity, minHeight: 136)
        .padding(Theme.Spacing.xs)
        .background(selected ? Theme.Colors.surfaceRaised : Theme.Colors.surface)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(onCar ? Theme.Colors.accent : selected ? Theme.Colors.signalYellow : Theme.Colors.separator, lineWidth: selected || onCar ? 2 : 1))
        .accessibilityElement(children: .combine)
    }

    private var compoundColor: Color {
        switch index {
        case 0: Theme.Colors.signalYellow
        case 1: Theme.Colors.accent
        default: Theme.Colors.signalBlue
        }
    }
}

private struct PresetActiveConfigCard: View {
    var model: PresetSyncModel
    let isConnected: Bool
    let isActiveConfigCurrent: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text("CONTROLLER CONFIG").themeLabel()
                    Spacer()
                    Text(isConnected && isActiveConfigCurrent && model.refreshError == nil && model.active != nil ? "CONFIRMED" : "UNVERIFIED")
                        .themeLabel(isConnected && isActiveConfigCurrent && model.refreshError == nil && model.active != nil ? Theme.Colors.signalTeal : Theme.Colors.signalYellow)
                }
                Text(headline).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                if let detail {
                    Text(detail).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private var headline: String {
        guard isActiveConfigCurrent else { return isConnected ? "Reading…" : "Unknown" }
        guard let active = model.active else { return isConnected && model.refreshError == nil ? "Reading…" : "Unknown" }
        if active.isFactory { return "Factory" }
        if let preset = model.presets.first(where: { $0.id == active.presetID }) { return preset.name }
        return active.source == .known(.persistedOverride) ? "Custom config" : "No config"
    }

    private var detail: String? {
        if !isConnected { return "Connect to check which configuration is running on the car." }
        if let error = model.refreshError { return error }
        guard let active = model.active else { return nil }
        if active.bootDiagnostic != nil {
            return "The saved config failed to load at start-up, so the controller runs its factory config."
        }
        if active.lightingSetupFailed {
            return "Lighting failed to start with this config. Send another preset or revert to factory."
        }
        return nil
    }
}

#if DEBUG
#Preview {
    NavigationStack { PresetsView(link: PresetPreviewSupport.link()) }
        .preferredColorScheme(.dark)
}
#endif
