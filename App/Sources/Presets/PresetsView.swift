import SwiftUI
import DesignSystem
import PresetSync
import CompanionProtocol

/// Lists the bundled presets, shows which config the controller runs, and
/// offers Revert to factory. Push it inside a `NavigationStack`.
///
/// Home links here once it has a `PresetSyncLink` for the connected
/// controller; `onChange` lets Home re-read the controller after a push or
/// revert is confirmed.
struct PresetsView: View {
    @State private var model: PresetSyncModel

    init(link: PresetSyncLink, onChange: (@MainActor () -> Void)? = nil) {
        let model = PresetSyncModel(presets: (try? PresetCatalog.bundled()) ?? [], link: link)
        model.onChange = onChange
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("PRESETS")
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Colors.textPrimary)

                ActiveConfigCard(model: model)

                Text("Bundled presets").themeLabel()
                if model.presets.isEmpty {
                    Text("No presets are bundled with this build.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                ForEach(model.presets) { preset in
                    NavigationLink {
                        PresetDetailView(preset: preset, model: model)
                    } label: {
                        Card(edge: model.active?.presetID == preset.id ? Theme.Colors.signalTeal : nil) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                HStack {
                                    Text(preset.name.uppercased())
                                        .font(Theme.Typography.headline)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Spacer()
                                    if model.active?.presetID == preset.id {
                                        StatusPill("Active", status: .live)
                                    }
                                }
                                Text(preset.summary)
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button("Revert to factory") { model.requestRevert() }
                    .buttonStyle(.secondary)
                    .disabled(model.phase.isBusy)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .presetSyncSheet(model: model) { $0 == .factory }
    }
}

/// What the controller runs now, from the last read.
private struct ActiveConfigCard: View {
    var model: PresetSyncModel

    var body: some View {
        Card(edge: Theme.Colors.accent) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Active config").themeLabel()
                Text(headline)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private var headline: String {
        guard let active = model.active else {
            return model.refreshError == nil ? "Reading…" : "Unknown"
        }
        if active.isFactory { return "Factory" }
        if let id = active.presetID, let preset = model.presets.first(where: { $0.id == id }) {
            return preset.name
        }
        if active.source == .known(.persistedOverride) { return "Custom config" }
        return "No config"
    }

    private var detail: String? {
        if let error = model.refreshError { return error }
        guard let active = model.active else { return nil }
        if active.bootDiagnostic != nil {
            return "The saved config failed to load at start-up, so the controller runs its factory config."
        }
        if active.lightingSetupFailed {
            return "Lighting failed to start with this config. Push another preset or revert to factory."
        }
        return nil
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PresetsView(link: PresetPreviewSupport.link())
    }
    .preferredColorScheme(.dark)
}
#endif
