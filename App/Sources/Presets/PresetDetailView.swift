import SwiftUI
import DesignSystem
import PresetSync

/// One preset: what each action does, in plain language, and the push button.
struct PresetDetailView: View {
    let preset: Preset
    var model: PresetSyncModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Preset").themeLabel(Theme.Colors.textSecondary)
                    Text(preset.name.uppercased())
                        .font(Theme.Typography.display)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(preset.summary)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text("What it does").themeLabel()
                ForEach(preset.actionDescriptions) { action in
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(action.title.uppercased())
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(action.detail)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }

                Button("Push to controller") { model.requestPush(preset) }
                    .buttonStyle(.primary)
                    .disabled(model.phase.isBusy)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .presetSyncSheet(model: model) { $0 == .preset(preset) }
    }
}
