import SwiftUI
import UIKit
import DesignSystem
import CompanionProtocol
import PresetSync

/// Edits one output binding in the draft: its kind and the settings that kind uses.
struct EffectEditor: View {
    var selection: SetupSelection
    let index: Int

    var body: some View {
        if let output {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(ConfigDescriber.effect(of: output))
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .unknown = output {
                    Text("Unsupported output is read-only and will be preserved when you edit other settings.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Picker("Effect type", selection: kindBinding) {
                        ForEach(EffectKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("setup.output.\(index).kind")
                    if case .ledEffect(let binding) = output {
                        Picker("Built-in effect", selection: builtInBinding(binding)) {
                            ForEach(ControllerConfig.LedEffect.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .font(Theme.Typography.body)
                        .tint(Theme.Colors.textPrimary)
                        .accessibilityIdentifier("setup.output.\(index).builtIn")
                    }
                    if let zone = output.zoneBinding { zoneControls(zone) }
                    if case .ledTransient(_, let durationMs) = output {
                        numericRow("FLASH MS", value: durationBinding(durationMs), id: "duration")
                    }
                    numericRow("PRIORITY", value: priorityBinding, id: "priority")
                    Button("Remove effect", systemImage: "minus.circle", role: .destructive) {
                        edit { $0.outputs.remove(at: index) }
                    }
                    .font(Theme.Typography.body)
                    .tint(Theme.Colors.accentText)
                    .accessibilityIdentifier("setup.output.\(index).remove")
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).stroke(Theme.Colors.separator))
        }
    }

    private var output: ControllerConfig.OutputBinding? {
        guard let outputs = selection.editableConfig?.outputs, outputs.indices.contains(index) else { return nil }
        return outputs[index]
    }

    @ViewBuilder
    private func zoneControls(_ binding: ControllerConfig.ZoneBinding) -> some View {
        ColorPicker("Colour", selection: colourBinding, supportsOpacity: false)
            .font(Theme.Typography.headline)
            .accessibilityIdentifier("setup.output.\(index).colour")
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(SetupColour.allCases) { colour in
                Button { changeZone { $0.color = colour.controllerColour } } label: {
                    RoundedRectangle(cornerRadius: Theme.Radius.xs)
                        .fill(colour.displayColour)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(
                            binding.color == colour.controllerColour ? Theme.Colors.textPrimary : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Colour \(colour.rawValue)")
                .accessibilityIdentifier("setup.output.\(index).colour.\(colour.rawValue)")
            }
        }
        numericRow("ZONE START", value: zoneBinding(\.start), id: "start")
        numericRow("LED COUNT", value: zoneBinding(\.length), id: "length")
        Picker("Direction", selection: directionBinding) {
            ForEach(ControllerConfig.FillDirection.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .font(Theme.Typography.body)
        .tint(Theme.Colors.textPrimary)
        .accessibilityIdentifier("setup.output.\(index).direction")
    }

    private func numericRow(_ label: String, value: Binding<Int>, id: String) -> some View {
        HStack {
            Text(label).themeLabel()
            Spacer()
            SetupNumberField(label: label, value: value, id: "setup.output.\(index).\(id)") {
                selection.setFieldValidity("setup.output.\(index).\(id)", isValid: $0)
            }
        }
    }

    private var kindBinding: Binding<EffectKind> {
        Binding(get: { output?.effectKind ?? .solid }, set: { kind in
            edit { $0.outputs[index] = $0.outputs[index].converted(to: kind) }
        })
    }

    private func builtInBinding(_ binding: ControllerConfig.EffectBinding) -> Binding<ControllerConfig.LedEffect> {
        Binding(get: { binding.effect }, set: { effect in
            var updated = binding
            updated.effect = effect
            edit { $0.outputs[index] = .ledEffect(updated) }
        })
    }

    private func durationBinding(_ fallback: Int) -> Binding<Int> {
        Binding(get: {
            if case .ledTransient(_, let durationMs) = output { return durationMs }
            return fallback
        }, set: { value in
            guard case .ledTransient(let binding, _) = output else { return }
            edit { $0.outputs[index] = .ledTransient(binding, durationMs: value) }
        })
    }

    private var priorityBinding: Binding<Int> {
        Binding(get: { output?.priority ?? ControllerConfig.OutputBinding.defaultPriority }, set: { value in
            edit { $0.outputs[index] = $0.outputs[index].replacingPriority(value) }
        })
    }

    private func zoneBinding(_ keyPath: WritableKeyPath<ControllerConfig.Zone, Int>) -> Binding<Int> {
        Binding(get: { output?.zoneBinding?.zone[keyPath: keyPath] ?? 0 }, set: { value in
            changeZone { $0.zone[keyPath: keyPath] = value }
        })
    }

    private var directionBinding: Binding<ControllerConfig.FillDirection> {
        Binding(get: { output?.zoneBinding?.zone.direction ?? .startToEnd }, set: { value in
            changeZone { $0.zone.direction = value }
        })
    }

    private var colourBinding: Binding<Color> {
        Binding(get: { output?.zoneBinding?.color.swiftUIColor ?? .white }, set: { value in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(value).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            changeZone { $0.color = .init(red: byte(red), green: byte(green), blue: byte(blue)) }
        })
    }

    private func byte(_ channel: CGFloat) -> Int { Int((min(1, max(0, channel)) * 255).rounded()) }

    private func changeZone(_ change: (inout ControllerConfig.ZoneBinding) -> Void) {
        guard var binding = output?.zoneBinding else { return }
        change(&binding)
        edit { $0.outputs[index] = $0.outputs[index].replacingZone(binding) }
    }

    private func edit(_ change: (inout ControllerConfig) -> Void) {
        guard var config = selection.editableConfig, config.outputs.indices.contains(index) else { return }
        change(&config)
        selection.updateConfig(config)
    }
}

extension ControllerConfig.LedEffect {
    var title: String {
        switch self {
        case .leftTurn: "Left turn"
        case .rightTurn: "Right turn"
        case .brake: "Brake"
        }
    }
}
