import SwiftUI
import CompanionProtocol
import DesignSystem

/// A rule being edited in `RuleEditSheet`.
struct RuleEditRequest: Identifiable {
    let id = UUID()
    let index: Int
    let rule: ControllerConfig.Rule
}

/// Edits a rule's trigger. Edits stay local until the user saves the sheet.
struct RuleEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RuleDraft
    @State private var inputError: String?
    let request: RuleEditRequest
    let actions: [String]
    let signals: [SignalDescriptor]
    let onSave: (ControllerConfig.Rule) -> Void

    init(request: RuleEditRequest, actions: [String], signals: [SignalDescriptor],
         onSave: @escaping (ControllerConfig.Rule) -> Void) {
        self.request = request
        self.actions = actions
        self.signals = signals.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
        self.onSave = onSave
        _draft = State(initialValue: RuleDraft(request.rule))
    }

    var body: some View {
        NavigationStack {
            Form {
                identityFields
                if draft.kind == .range { rangeFields }
                if draft.kind != .range { conditionFields }
                behaviorFields
                if let inputError {
                    Text(inputError).foregroundStyle(Theme.Colors.signalYellow).listRowBackground(Theme.Colors.surface)
                        .accessibilityIdentifier("rule.inputError")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.signalBlueText)
            .navigationTitle(request.index == nil ? "ADD RULE" : "EDIT RULE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("rule.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(draft.actionName.isEmpty)
                        .accessibilityIdentifier("rule.save")
                }
            }
            .onChange(of: draft.signalKey) { _, signal in
                if signal == "vehicle.brake_pressed" { draft.freshness = .freshOrUnverified }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var identityFields: some View {
        Section {
            Picker(selection: $draft.kind) {
                ForEach(RuleDraft.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: { Text("Rule type").themeLabel() }
            .accessibilityIdentifier("rule.kind")
            actionField
            signalField
        } header: { Text("Rule").themeLabel() }
        .listRowBackground(Theme.Colors.surface)
    }

    /// Any name the user types; the setup's existing actions are offered as shortcuts.
    private var actionField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Action").themeLabel()
            TextField("door_open", text: $draft.action)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("Action").accessibilityIdentifier("rule.action")
            if !actions.isEmpty {
                Menu("Existing actions") {
                    ForEach(actions, id: \.self) { action in
                        Button(action) { draft.action = action }
                    }
                }.accessibilityIdentifier("rule.actionSuggestions")
            }
            if !draft.actionName.isEmpty, !actions.contains(draft.actionName) {
                Text("New action. It has no output yet, so the controller will not light anything for it.")
                    .font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("rule.action.new")
            }
        }
    }

    /// Discovered signals are chosen from the catalog; typed keys remain only before discovery.
    @ViewBuilder private var signalField: some View {
        if signals.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Signal key").themeLabel()
                TextField("vehicle.engine_rpm", text: $draft.signalKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Signal key").accessibilityIdentifier("rule.signal")
                Menu("Known signals") {
                    ForEach(["vehicle.engine_rpm", "vehicle.brake_pressed", "vehicle.turn_state"], id: \.self) { signal in
                        Button(signal) { draft.signalKey = signal }
                    }
                }.accessibilityIdentifier("rule.signalSuggestions")
            }
        } else {
            Picker(selection: signalSelection) {
                if selectedSignal == nil {
                    Text(draft.signalKey.isEmpty ? "Choose a signal" : "\(draft.signalKey) (not discovered)")
                        .tag(draft.signalKey)
                }
                ForEach(signals, id: \.handle) { signal in
                    VStack(alignment: .leading) {
                        Text(signal.key).font(.system(.body, design: .monospaced))
                        Text(signal.menuDetail).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .tag(signal.key)
                }
            } label: { Text("Signal").themeLabel() }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("rule.signal")
        }
    }

    /// Choosing a discovered signal also matches the operand to its catalog type.
    private var signalSelection: Binding<String> {
        Binding {
            draft.signalKey
        } set: { key in
            if let signal = signals.first(where: { $0.key.utf8.elementsEqual(key.utf8) }) {
                draft.select(signal)
            } else {
                draft.signalKey = key
            }
        }
    }

    private var selectedSignal: SignalDescriptor? {
        signals.first { $0.key.utf8.elementsEqual(draft.signalKey.utf8) }
    }

    private var conditionFields: some View {
        Section {
            Picker(selection: $draft.comparison) {
                ForEach(ControllerConfig.Comparison.allCases, id: \.self) {
                    Text($0.rawValue.replacingOccurrences(of: "_", with: " ")).tag($0)
                }
            } label: { Text("Comparison").themeLabel() }
            .accessibilityIdentifier("rule.comparison")
            Picker(selection: $draft.operandKind) {
                ForEach(RuleDraft.OperandKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            } label: { Text("Operand type").themeLabel() }
            .accessibilityIdentifier("rule.operandKind")
            operandField
        } header: { Text("Condition").themeLabel() }
        .listRowBackground(Theme.Colors.surface)
    }

    @ViewBuilder private var operandField: some View {
        switch draft.operandKind {
        case .boolean:
            Toggle(isOn: $draft.boolean) { Text("Operand is true").themeLabel() }
                .accessibilityIdentifier("rule.operand.boolean")
        case .number: numericField("Operand", text: $draft.number, id: "rule.operand.number")
        case .choice:
            TextField("Choice key", text: $draft.choice)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Choice key").accessibilityIdentifier("rule.operand.choice")
            if let choices = selectedSignal?.choices, !choices.isEmpty {
                Menu("Signal choices") {
                    ForEach(choices, id: \.handle) { choice in
                        Button(choice.key) { draft.choice = choice.key }
                    }
                }.accessibilityIdentifier("rule.operand.choiceSuggestions")
            }
        }
    }

    private var rangeFields: some View {
        Section {
            numericField("Input from", text: $draft.inputFrom, id: "rule.input.from")
            numericField("Input to", text: $draft.inputTo, id: "rule.input.to")
            numericField("Output from", text: $draft.outputFrom, id: "rule.output.from")
            numericField("Output to", text: $draft.outputTo, id: "rule.output.to")
        } header: { Text("Range mapping").themeLabel() }
        .listRowBackground(Theme.Colors.surface)
    }

    private var behaviorFields: some View {
        Section {
            if draft.signalKey == "vehicle.brake_pressed" {
                LabeledContent { Text("FRESH OR UNVERIFIED") } label: { Text("Freshness").themeLabel() }
                    .accessibilityIdentifier("rule.brakeFreshness")
            } else {
                Picker(selection: $draft.freshness) {
                    ForEach(draft.availableFreshness, id: \.self) {
                        Text($0.rawValue.replacingOccurrences(of: "_", with: " ").uppercased()).tag($0)
                    }
                } label: { Text("Freshness").themeLabel() }
                .accessibilityIdentifier("rule.freshness")
            }
            if draft.kind == .sampledState {
                Toggle(isOn: $draft.hasRelease) { Text("Release threshold").themeLabel() }
                    .accessibilityIdentifier("rule.release.enabled")
                if draft.hasRelease { numericField("Release threshold", text: $draft.release, id: "rule.release.value") }
            }
            if draft.kind == .event {
                Picker(selection: $draft.edge) {
                    ForEach(ControllerConfig.EventEdge.allCases, id: \.self) {
                        Text($0.rawValue.replacingOccurrences(of: "_", with: " ")).tag($0)
                    }
                } label: { Text("Event edge").themeLabel() }
                .accessibilityIdentifier("rule.edge")
            }
        } header: { Text("Behavior").themeLabel() }
        .listRowBackground(Theme.Colors.surface)
    }

    private func numericField(_ title: String, text: Binding<String>, id: String) -> some View {
        HStack {
            Text(title).themeLabel()
            TextField(title, text: text).multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityLabel(title).accessibilityIdentifier(id)
        }
    }

    private func save() {
        do {
            onSave(try draft.makeRule())
            dismiss()
        } catch RuleDraft.InputError.number(let field) {
            inputError = "Enter a finite number for \(field.lowercased())."
        } catch RuleDraft.InputError.missingAction {
            inputError = "Enter an action name."
        } catch RuleDraft.InputError.wholeRPM(let field) {
            inputError = "Enter a whole-number RPM for \(field.lowercased())."
        } catch {
            inputError = "This rule could not be saved."
        }
    }
}

private extension SignalDescriptor {
    var menuDetail: String {
        let type = switch type.known {
        case .boolean: "Boolean"
        case .number: "Number"
        case .enumeration: "Enum · \(choices.count) choices"
        case nil: "Unsupported type (\(type.rawValue))"
        }
        return unit == "none" ? type : "\(type) · \(unit)"
    }
}
