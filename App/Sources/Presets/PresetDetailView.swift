import SwiftUI
import DesignSystem
import PresetSync

/// Shared presentation of a preset's complete, read-only action descriptions.
struct PresetActionList: View {
    let preset: Preset

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(preset.name.uppercased()).font(Theme.Typography.headline)
                Text(preset.summary).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                Text("COMPLETE PRESET · \(preset.actionDescriptions.count) ACTIONS").themeLabel()
            }
            ForEach(preset.actionDescriptions) { action in
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(action.title.uppercased()).font(Theme.Typography.headline)
                        Text(action.detail).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
    }
}
