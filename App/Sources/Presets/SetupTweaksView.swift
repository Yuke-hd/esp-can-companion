import SwiftUI
import UIKit
import DesignSystem
import PresetSync
import CompanionProtocol

/// Common lighting adjustments over the same complete draft used by the rule editor.
struct SetupTweaksView: View {
    var selection: SetupSelection

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let range = selection.tweaks?.rpmInputRange {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        sectionHeader("RPM FILL", detail: "RANGE · ENGINE RPM", color: Theme.Colors.signalBlueText)
                        rpmControl("INPUT FROM", id: "rpm.from", value: rpmRangeBinding(lower: true, fallback: range),
                                   error: selection.rpmError(for: .rpmFill, field: .inputFrom))
                        rpmControl("INPUT TO", id: "rpm.to", value: rpmRangeBinding(lower: false, fallback: range),
                                   error: selection.rpmError(for: .rpmFill, field: .inputTo))
                        outputControls(.rpmFill)
                    }
                }
            }
            if let thresholds = selection.tweaks?.redZoneThresholds {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        sectionHeader("RED ZONE", detail: "SAMPLED STATE", color: Theme.Colors.signalPurple)
                        rpmControl("TRIGGER THRESHOLD", id: "red.trigger", value: thresholdBinding(release: false, fallback: thresholds),
                                   tint: Theme.Colors.accent, error: selection.rpmError(for: .redZone, field: .trigger))
                        Toggle("Separate release threshold", isOn: hysteresisBinding(thresholds))
                            .font(Theme.Typography.body)
                            .tint(Theme.Colors.signalTeal)
                            .accessibilityIdentifier("setup.red.hysteresis")
                        if thresholds.releaseBelow != nil {
                            rpmControl("RELEASE BELOW", id: "red.release", value: thresholdBinding(release: true, fallback: thresholds),
                                       error: selection.rpmError(for: .redZone, field: .release))
                        }
                        outputControls(.redZone)
                    }
                }
            }
            if selection.tweaks?.output(for: .brake) != nil {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        sectionHeader("BRAKE", detail: "OUTPUT SETTINGS", color: Theme.Colors.signalYellow)
                        outputControls(.brake)
                    }
                }
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    @ViewBuilder
    private func outputControls(_ action: SetupAction) -> some View {
        if let settings = selection.tweaks?.output(for: action) {
            SetupOutputControls(selection: selection, action: action, settings: settings)
        }
    }

    private func sectionHeader(_ title: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title).font(Theme.Typography.headline).accessibilityAddTraits(.isHeader)
            Text(detail).themeLabel(color)
        }
    }

    private func rpmControl(_ label: String, id: String, value: Binding<Double>, tint: Color = Theme.Colors.signalBlue,
                            error: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label).themeLabel()
                Spacer()
                SetupNumberField(label: label, value: value, id: "setup.\(id)", integerOnly: true) {
                    selection.setFieldValidity("setup.\(id)", isValid: $0)
                }
                Text("RPM").themeLabel()
            }
            if let error { RPMValidationMessage(message: error, id: "setup.\(id).validation") }
            Slider(value: rpmSliderBinding(value), in: RPMValidation.allowedRange, step: 100)
                .tint(tint)
                .accessibilityLabel(label)
                .accessibilityIdentifier("setup.\(id).slider")
        }
    }

    private func rpmRangeBinding(lower: Bool, fallback: RPMInputRange) -> Binding<Double> {
        Binding(get: {
            let range = selection.tweaks?.rpmInputRange ?? fallback
            return lower ? range.lower : range.upper
        }, set: { value in
            let range = selection.tweaks?.rpmInputRange ?? fallback
            selection.setRPMInputRange(.init(lower: lower ? value : range.lower, upper: lower ? range.upper : value))
        })
    }

    private func thresholdBinding(release: Bool, fallback: RedZoneThresholds) -> Binding<Double> {
        Binding(get: {
            let thresholds = selection.tweaks?.redZoneThresholds ?? fallback
            return release ? thresholds.releaseBelow ?? thresholds.triggerAbove : thresholds.triggerAbove
        }, set: { value in
            let thresholds = selection.tweaks?.redZoneThresholds ?? fallback
            selection.setRedZoneThresholds(.init(triggerAbove: release ? thresholds.triggerAbove : value,
                                                 releaseBelow: release ? value : thresholds.releaseBelow))
        })
    }

    private func hysteresisBinding(_ fallback: RedZoneThresholds) -> Binding<Bool> {
        Binding(get: { selection.tweaks?.redZoneThresholds?.releaseBelow != nil }, set: { enabled in
            let thresholds = selection.tweaks?.redZoneThresholds ?? fallback
            selection.setRedZoneThresholds(.init(triggerAbove: thresholds.triggerAbove,
                                                 releaseBelow: enabled ? max(0, thresholds.triggerAbove - 200) : nil))
        })
    }
}

struct RPMValidationMessage: View {
    let message: String
    let id: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Theme.Colors.signalYellow)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }
}

/// Normalize drag values before they reach the draft; text entry uses the original binding.
func rpmSliderBinding(_ value: Binding<Double>) -> Binding<Double> {
    Binding(get: { value.wrappedValue }, set: { draggedValue in
        guard draggedValue.isFinite else { return }
        value.wrappedValue = (draggedValue / 100).rounded() * 100
    })
}

private struct SetupOutputControls: View {
    var selection: SetupSelection
    let action: SetupAction
    let settings: ActionOutputSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Divider().overlay(Theme.Colors.separator)
            ColorPicker("Colour", selection: colourBinding, supportsOpacity: false)
                .font(Theme.Typography.headline)
                .accessibilityIdentifier("setup.\(action.rawValue).colour")
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(SetupColour.allCases) { colour in
                    Button { changeColour(colour.controllerColour) } label: {
                        RoundedRectangle(cornerRadius: Theme.Radius.xs)
                            .fill(colour.displayColour)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(
                                current.color == colour.controllerColour ? Theme.Colors.textPrimary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(action.rawValue.replacingOccurrences(of: "_", with: " ")) colour \(colour.rawValue)")
                    .accessibilityIdentifier("setup.\(action.rawValue).colour.\(colour.rawValue)")
                }
            }
            numericRow("ZONE START", value: zoneBinding(\.start), id: "start")
            numericRow("LED COUNT", value: zoneBinding(\.length), id: "length")
            Picker("Direction", selection: directionBinding) {
                ForEach(ControllerConfig.FillDirection.allCases, id: \.self) { direction in
                    Text(direction.title).tag(direction)
                }
            }
            .font(Theme.Typography.body)
            .tint(Theme.Colors.textPrimary)
            .accessibilityIdentifier("setup.\(action.rawValue).direction")
            numericRow("PRIORITY", value: priorityBinding, id: "priority")
        }
    }

    private var current: ActionOutputSettings { selection.tweaks?.output(for: action) ?? settings }

    private func numericRow(_ label: String, value: Binding<Int>, id: String) -> some View {
        HStack {
            Text(label).themeLabel()
            Spacer()
            SetupNumberField(label: label, value: value, id: "setup.\(action.rawValue).\(id)") {
                selection.setFieldValidity("setup.\(action.rawValue).\(id)", isValid: $0)
            }
        }
    }

    private func zoneBinding(_ keyPath: WritableKeyPath<ControllerConfig.Zone, Int>) -> Binding<Int> {
        Binding(get: { current.zone[keyPath: keyPath] }, set: { value in
            var zone = current.zone
            zone[keyPath: keyPath] = value
            selection.setOutput(.init(color: current.color, zone: zone, priority: current.priority), for: action)
        })
    }

    private var directionBinding: Binding<ControllerConfig.FillDirection> {
        Binding(get: { current.zone.direction }, set: { value in
            var zone = current.zone
            zone.direction = value
            selection.setOutput(.init(color: current.color, zone: zone, priority: current.priority), for: action)
        })
    }

    private var priorityBinding: Binding<Int> {
        Binding(get: { current.priority }, set: { value in
            selection.setOutput(.init(color: current.color, zone: current.zone, priority: value), for: action)
        })
    }

    private var colourBinding: Binding<Color> {
        Binding(get: { current.color.swiftUIColor }, set: { value in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(value).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            changeColour(.init(red: byte(red), green: byte(green), blue: byte(blue)))
        })
    }

    private func byte(_ channel: CGFloat) -> Int { Int((min(1, max(0, channel)) * 255).rounded()) }

    private func changeColour(_ colour: ControllerConfig.Color) {
        selection.setOutput(.init(color: colour, zone: current.zone, priority: current.priority), for: action)
    }
}

/// A numeric entry with a return key, avoiding an undismissable number-pad keyboard.
private struct SetupNumberField<Value: Numeric & LosslessStringConvertible>: View {
    let label: String
    @Binding var value: Value
    let id: String
    let integerOnly: Bool
    let onValidityChanged: (Bool) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(label: String, value: Binding<Value>, id: String, integerOnly: Bool = false, onValidityChanged: @escaping (Bool) -> Void) {
        self.label = label
        _value = value
        self.id = id
        self.integerOnly = integerOnly
        self.onValidityChanged = onValidityChanged
        _text = State(initialValue: SetupNumericEntry.formatted(value.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
            entry
            if !isRepresentable {
                Text(integerOnly ? "Enter a whole-number RPM" : "Enter a finite number")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.signalYellow)
                    .accessibilityIdentifier("\(id).error")
            }
        }
        .onAppear { onValidityChanged(isRepresentable) }
        .onDisappear { onValidityChanged(true) }
    }

    private var entry: some View {
        TextField(label, text: $text)
            .font(Theme.Typography.value)
            .multilineTextAlignment(.trailing)
            .keyboardType(.numbersAndPunctuation)
            .submitLabel(.done)
            .focused($focused)
            .onSubmit { focused = false }
            .onChange(of: text) { _, entry in
                onValidityChanged(isRepresentable)
                if let number: Value = SetupNumericEntry.parse(entry, integerOnly: integerOnly) { value = number }
            }
            .onChange(of: value) { _, number in
                if !focused { text = SetupNumericEntry.formatted(number) }
            }
            .onChange(of: focused) { _, editing in
                if !editing && isRepresentable { text = SetupNumericEntry.formatted(value) }
            }
            .frame(width: 108)
            .padding(Theme.Spacing.xs)
            .background(Theme.Colors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(Theme.Colors.separator, lineWidth: 1))
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }

    private var isRepresentable: Bool {
        let number: Value? = SetupNumericEntry.parse(text, integerOnly: integerOnly)
        return number != nil
    }
}

private enum SetupColour: String, CaseIterable, Identifiable {
    case red, blue, teal, purple, yellow, white
    var id: Self { self }
    var controllerColour: ControllerConfig.Color {
        switch self {
        case .red: .init(red: 32, green: 0, blue: 0)
        case .blue: .init(red: 0, green: 0, blue: 32)
        case .teal: .init(red: 0, green: 32, blue: 28)
        case .purple: .init(red: 20, green: 0, blue: 32)
        case .yellow: .init(red: 32, green: 25, blue: 0)
        case .white: .init(red: 32, green: 32, blue: 32)
        }
    }
    var displayColour: Color {
        let colour = controllerColour
        return Color(red: Double(colour.red) / 32, green: Double(colour.green) / 32, blue: Double(colour.blue) / 32)
    }
}

private extension ControllerConfig.Color {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

private extension ControllerConfig.FillDirection {
    var title: String {
        switch self {
        case .startToEnd: "Start to end"
        case .endToStart: "End to start"
        case .centerOut: "Centre out"
        }
    }
}
