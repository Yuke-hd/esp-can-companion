import SwiftUI
import UIKit
import DesignSystem
import PresetSync
import CompanionProtocol

/// Every rule in the draft as a collapsible card: what triggers it and what
/// its action shows. RPM fill and red zone keep their inline RPM controls.
struct SetupRulesView: View {
    var selection: SetupSelection
    /// The connected controller's catalog; empty when none has been discovered.
    var signals: [SignalDescriptor] = []
    var outputCatalog: OutputCatalog? = nil
    @State private var expanded: Set<Int> = []
    @State private var editing: RuleEditRequest?

    var body: some View {
        if let config = selection.editableConfig {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let outputCatalog {
                    OutputCatalogEditor(selection: selection, catalog: outputCatalog)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("RULES").font(Theme.Typography.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(config.rules.count) RULES").themeLabel()
                }
                ForEach(config.rules.indices, id: \.self) { index in
                    ruleCard(config.rules[index], at: index, in: config)
                }
                Button("ADD RULE", systemImage: "plus") { addRule() }
                    .font(Theme.Typography.headline)
                    .tint(Theme.Colors.signalBlueText)
                    .accessibilityIdentifier("rules.add")
                Text("Controller validates the full setup when you send it to the car.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .sheet(item: $editing) { request in
                RuleEditSheet(request: request, actions: config.actions.map(\.name), signals: signals) { rule in
                    save(rule, at: request.index)
                }
            }
        }
    }

    private func ruleCard(_ rule: ControllerConfig.Rule, at index: Int, in config: ControllerConfig) -> some View {
        let isExpanded = expanded.contains(index)
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Button { toggle(index) } label: { ruleHeader(rule, in: config, isExpanded: isExpanded) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ConfigDescriber.title(rule.action)), \(isExpanded ? "collapse" : "expand")")
                    .accessibilityIdentifier("rules.toggle.\(index)")
                // Expanded RPM cards show these under each field instead.
                if !isExpanded || !hasInlineRPMControls(at: index) {
                    ForEach(RPMValidation.issues(in: config).filter { $0.ruleIndex == index }) { issue in
                        RPMValidationMessage(message: issue.summary, id: "rule.\(issue.id).validation")
                    }
                }
                if isExpanded {
                    Divider().overlay(Theme.Colors.separator)
                    ActionNameField(name: rule.action, id: "rules.name.\(index)",
                                    isReserved: ControllerConfig.isReservedAction(rule.action)) { rename(rule.action, to: $0) }
                        .id("\(index).\(rule.action)")
                    triggerSection(rule, at: index)
                    Divider().overlay(Theme.Colors.separator)
                    effectSection(rule, at: index, in: config)
                    Button("Delete rule", systemImage: "trash", role: .destructive) { deleteRule(at: index) }
                        .font(Theme.Typography.body)
                        .tint(Theme.Colors.accentText)
                        .accessibilityIdentifier("rules.delete.\(index)")
                }
            }
        }
    }

    private func ruleHeader(_ rule: ControllerConfig.Rule, in config: ControllerConfig, isExpanded: Bool) -> some View {
        let draft = RuleDraft(rule)
        return HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(ConfigDescriber.title(rule.action).uppercased()).font(Theme.Typography.headline)
                Text("\(draft.kind.title) · \(draft.signalKey)").themeLabel(Theme.Colors.signalPurple)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let colour = config.outputs.first(where: { $0.action == rule.action })?.zoneBinding?.color {
                RoundedRectangle(cornerRadius: Theme.Radius.xs)
                    .fill(colour.previewColor)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .foregroundStyle(Theme.Colors.signalBlueText)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func triggerSection(_ rule: ControllerConfig.Rule, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("TRIGGER").themeLabel(Theme.Colors.signalBlueText)
            if index == selection.tweaks?.rpmRuleIndex, let range = selection.tweaks?.rpmInputRange {
                rpmControl("INPUT FROM", id: "rpm.from", value: rpmRangeBinding(lower: true, fallback: range),
                           error: selection.rpmError(for: .rpmFill, field: .inputFrom))
                rpmControl("INPUT TO", id: "rpm.to", value: rpmRangeBinding(lower: false, fallback: range),
                           error: selection.rpmError(for: .rpmFill, field: .inputTo))
            } else if index == selection.tweaks?.redZoneRuleIndex, let thresholds = selection.tweaks?.redZoneThresholds {
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
            } else {
                Text(ConfigDescriber.trigger(rule))
                    .font(Theme.Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Edit trigger", systemImage: "slider.horizontal.3") {
                editing = RuleEditRequest(index: index, rule: rule)
            }
            .font(Theme.Typography.body)
            .tint(Theme.Colors.signalBlueText)
            .accessibilityIdentifier("rules.edit.\(index)")
        }
    }

    @ViewBuilder
    private func effectSection(_ rule: ControllerConfig.Rule, at index: Int, in config: ControllerConfig) -> some View {
        let outputIndices = config.outputs.indices.filter { config.outputs[$0].action == rule.action }
        let sharing = config.rules.indices.filter { $0 != index && config.rules[$0].action == rule.action }.count
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("EFFECT").themeLabel(Theme.Colors.signalBlueText)
            if sharing > 0 {
                Text("Shared with \(sharing) other \(sharing == 1 ? "rule" : "rules") using this action.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(outputIndices, id: \.self) { outputIndex in
                let output = config.outputs[outputIndex]
                let isReadOnly = outputCatalog.map { !OutputCatalogEditor.isEditable(output, in: $0) } ?? false
                EffectEditor(selection: selection, index: outputIndex, isReadOnly: isReadOnly)
            }
            if outputIndices.isEmpty {
                Text("This rule's action shows nothing yet.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Button(outputIndices.isEmpty ? "Add effect" : "Add another effect", systemImage: "plus") {
                edit { $0.outputs.append(.solid(for: rule.action)) }
            }
            .font(Theme.Typography.body)
            .tint(Theme.Colors.signalBlueText)
            .accessibilityIdentifier("rules.addEffect.\(index)")
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

    private func hasInlineRPMControls(at index: Int) -> Bool {
        index == selection.tweaks?.rpmRuleIndex || index == selection.tweaks?.redZoneRuleIndex
    }

    private func toggle(_ index: Int) {
        withAnimation(.snappy) {
            if expanded.contains(index) { expanded.remove(index) } else { expanded.insert(index) }
        }
    }

    private func edit(_ change: (inout ControllerConfig) -> Void) {
        guard var config = selection.editableConfig else { return }
        change(&config)
        selection.updateConfig(config)
    }

    /// Returns an error message, or `nil` once the name is saved.
    private func rename(_ action: String, to text: String) -> String? {
        guard var config = selection.editableConfig else { return nil }
        do {
            try config.renameAction(action, to: text)
        } catch ControllerConfig.RenameError.taken {
            return "Another action already uses that name."
        } catch ControllerConfig.RenameError.reserved {
            return "That name is used by a built-in action."
        } catch {
            return "Enter a name with at least one letter or number."
        }
        selection.updateConfig(config)
        return nil
    }

    private func addRule() {
        var index = 0
        edit { index = $0.addCustomRule() }
        withAnimation(.snappy) { _ = expanded.insert(index) }
    }

    private func deleteRule(at index: Int) {
        edit { $0.removeRule(at: index) }
        expanded = Set(expanded.compactMap { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) })
    }

    private func save(_ rule: ControllerConfig.Rule, at index: Int?) {
        edit { $0.save(rule, at: index) }
        editing = nil
    }
}

/// Edits an action's name; the draft changes when the user submits or leaves the field.
private struct ActionNameField: View {
    let name: String
    let id: String
    let isReserved: Bool
    let onCommit: (String) -> String?
    @State private var text: String
    @State private var isEdited = false
    @State private var error: String?
    @FocusState private var focused: Bool

    init(name: String, id: String, isReserved: Bool, onCommit: @escaping (String) -> String?) {
        self.name = name
        self.id = id
        self.isReserved = isReserved
        self.onCommit = onCommit
        _text = State(initialValue: ConfigDescriber.title(name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("ACTION NAME").themeLabel(Theme.Colors.signalBlueText)
            if isReserved {
                Text(ConfigDescriber.title(name))
                    .font(Theme.Typography.body)
                    .accessibilityIdentifier(id)
                Text("Built-in actions keep their name.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                editableName
            }
        }
    }

    private var editableName: some View {
        Group {
            TextField("Action name", text: Binding(get: { text }, set: {
                guard text != $0 else { return }
                text = $0
                isEdited = true
            }))
                .font(Theme.Typography.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { focused = false }
                .onChange(of: focused) { _, editing in if !editing { commit() } }
                .onChange(of: name) { _, stored in
                    if !focused {
                        text = ConfigDescriber.title(stored)
                        isEdited = false
                    }
                }
                .onDisappear { commit() }
                .padding(Theme.Spacing.xs)
                .background(Theme.Colors.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(
                    error == nil ? Theme.Colors.separator : Theme.Colors.signalYellow, lineWidth: 1))
                .accessibilityLabel("Action name")
                .accessibilityIdentifier(id)
            if let error {
                RPMValidationMessage(message: error, id: "\(id).error")
            } else {
                let stored = isEdited ? ControllerConfig.actionName(from: text) : name
                Text("\(stored == name || stored.isEmpty ? "Saved as" : "Will save as") \(stored.isEmpty ? name : stored)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func commit() {
        guard isEdited else { return }
        error = onCommit(text)
        if error == nil {
            text = ConfigDescriber.title(ControllerConfig.actionName(from: text))
            isEdited = false
        }
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

/// A numeric entry with a return key, avoiding an undismissable number-pad keyboard.
struct SetupNumberField<Value: Numeric & LosslessStringConvertible>: View {
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

enum SetupColour: String, CaseIterable, Identifiable {
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

extension ControllerConfig.Color {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    /// The hue at full brightness, since controller colours are often dim.
    var previewColor: Color {
        let peak = Double(max(red, green, blue, 1))
        return Color(red: Double(red) / peak, green: Double(green) / peak, blue: Double(blue) / peak)
    }
}

extension ControllerConfig.FillDirection {
    var title: String {
        switch self {
        case .startToEnd: "Start to end"
        case .endToStart: "End to start"
        case .centerOut: "Centre out"
        }
    }
}
