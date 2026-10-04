import SwiftUI
import DesignSystem
import PresetSync

extension View {
    /// Presents the confirm, progress and verdict sheet while the model's
    /// phase concerns a target `presents` accepts.
    func presetSyncSheet(
        model: PresetSyncModel,
        presents: @escaping (PresetSyncModel.Target) -> Bool
    ) -> some View {
        sheet(isPresented: Binding(
            get: { model.phase.target.map(presents) ?? false },
            set: { if !$0 { model.dismiss() } }
        )) {
            PresetSyncSheet(model: model)
                .presentationDetents([.medium])
                .interactiveDismissDisabled(model.phase.isBusy)
        }
    }
}

/// Confirm, progress and the controller's verdict for one push or revert.
struct PresetSyncSheet: View {
    var model: PresetSyncModel

    var body: some View {
        let phase = model.phase
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(phase.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                StatusPill(phase.pillTitle, status: phase.pillStatus)
            }
            Text(phase.message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            switch phase {
            case .uploading(_, let fraction):
                ProgressView(value: fraction)
                    .tint(Theme.Colors.accent)
            case .validating, .reverting, .restarting:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .failed(_, let failure):
                if let code = failure.code {
                    DiagnosticRow(label: "Code", value: code)
                }
                if let field = failure.field {
                    DiagnosticRow(label: "Field", value: field)
                }
            default:
                EmptyView()
            }

            Spacer(minLength: 0)
            buttons(for: phase)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface.ignoresSafeArea())
    }

    @ViewBuilder
    private func buttons(for phase: PresetSyncModel.Phase) -> some View {
        switch phase {
        case .confirming(let target):
            Button(target == .factory ? "Revert" : "Push") {
                Task { await model.confirm() }
            }
            .buttonStyle(.primary)
            Button("Cancel") { model.dismiss() }
                .buttonStyle(.secondary)
        case .succeeded, .failed:
            Button("Done") { model.dismiss() }
                .buttonStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label).themeLabel()
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
        }
    }
}

extension PresetSyncModel.Phase {
    var target: PresetSyncModel.Target? {
        switch self {
        case .idle: nil
        case .confirming(let target), .restarting(let target), .succeeded(let target), .failed(let target, _): target
        case .uploading(let preset, _), .validating(let preset): .preset(preset)
        case .reverting: .factory
        }
    }

    var title: String {
        switch self {
        case .idle: ""
        case .confirming(.preset(let preset)): "Push \(preset.name)?"
        case .confirming(.factory): "Revert to factory?"
        case .uploading(let preset, _): "Sending \(preset.name)"
        case .validating: "Checking the preset"
        case .reverting: "Reverting"
        case .restarting: "Restarting"
        case .succeeded(.preset(let preset)): "\(preset.name) is running"
        case .succeeded(.factory): "Factory config is running"
        case .failed(_, let failure): failure.title
        }
    }

    var message: String {
        switch self {
        case .idle: ""
        case .confirming(.preset):
            "The controller checks the preset and keeps its current config if it finds a problem. "
                + "If the preset passes, the controller saves it and restarts; the lights go dark for a moment."
        case .confirming(.factory):
            "The controller clears the saved config and restarts with its factory config. The lights go dark for a moment."
        case .uploading: "Sending the preset to the controller."
        case .validating: "The controller is validating and saving the preset."
        case .reverting: "Asking the controller to clear its saved config."
        case .restarting: "Waiting for the controller to restart and checking which config it runs."
        case .succeeded(.preset): "The controller restarted and confirmed it runs this preset."
        case .succeeded(.factory): "The controller restarted and confirmed it runs its factory config."
        case .failed(_, let failure): failure.message
        }
    }

    var pillTitle: String {
        switch self {
        case .idle, .confirming: "Ready"
        case .uploading, .validating, .reverting, .restarting: "Working"
        case .succeeded: "Confirmed"
        case .failed(_, let failure): failure.kind == .rejected ? "Rejected" : "Failed"
        }
    }

    var pillStatus: StatusPill.Status {
        switch self {
        case .idle, .confirming: .neutral
        case .uploading, .validating, .reverting, .restarting: .pending
        case .succeeded: .live
        case .failed: .alert
        }
    }
}
