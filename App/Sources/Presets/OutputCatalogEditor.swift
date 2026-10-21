import SwiftUI
import DesignSystem
import CompanionProtocol

/// Edits controller-declared output fields while leaving config validation to firmware.
struct OutputCatalogEditor: View {
    let selection: SetupSelection
    let catalog: OutputCatalog

    private var config: ControllerConfig { selection.editableConfig ?? ControllerConfig() }
    private var bindingRecords: [BindingRecord] {
        config.outputs.enumerated().compactMap { index, binding in
            guard let value = Self.jsonValue(binding), let object = value.object,
                  let type = object["type"]?.stringValue else { return nil }
            return BindingRecord(index: index, type: type, action: object["action"]?.stringValue ?? "", value: value)
        }
    }
    private var unlistedRecords: [BindingRecord] {
        let types = Set(catalog.outputs.map(\.type))
        return bindingRecords.filter { !types.contains($0.type) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if !catalog.sinks.isEmpty {
                Text("OUTPUT SETTINGS").font(Theme.Typography.headline).accessibilityAddTraits(.isHeader)
                ForEach(catalog.sinks, id: \.sink) { sink in
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(humanize(sink.sink)).font(Theme.Typography.headline)
                            ForEach(sink.settings.filter(\.isEditable), id: \.name) { field in
                                integerField(field, value: sinkValue(sink.sink, field), id: "setup.sink.\(sink.sink).\(field.name)") { value in
                                    selection.setCatalogSinkSetting(field.name, value: .number(Double(value)), sink: sink.sink)
                                }
                            }
                        }
                    }
                }
            }

            ForEach(catalog.outputs, id: \.type) { output in
                let records = bindingRecords.filter { $0.type == output.type }
                ForEach(records) { record in
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(humanize(output.type)).font(Theme.Typography.headline)
                                .accessibilityAddTraits(.isHeader)
                            if output.isEditable && bindingIsEditable(record, for: output) {
                                ForEach(output.fields, id: \.name) { field in
                                    fieldEditor(field, output: output, record: record)
                                }
                            } else {
                                Text("This output contains a value this catalog does not describe, so it is read-only.")
                                    .font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                                rawJSON(record.value)
                            }
                        }
                    }
                }
                if output.isEditable {
                    Button("Add \(humanize(output.type))") { selection.addCatalogOutput(output) }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("setup.output.add.\(output.type)")
                }
            }

            ForEach(unlistedRecords) { record in
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Unsupported: \(humanize(record.type))").font(Theme.Typography.headline)
                        Text("This binding is read-only because the controller catalog does not list its type.")
                            .font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                        rawJSON(record.value)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldEditor(_ field: OutputCatalog.Field, output: OutputCatalog.Output, record: BindingRecord) -> some View {
        let value = record.value.object?[field.name] ?? defaultValue(field)
        switch field.kind {
        case "action":
            if config.actions.isEmpty {
                stringField(field.name, value: value.stringValue ?? "") { update(field, .string($0), output, record) }
            } else {
                Picker(humanize(field.name), selection: Binding(get: { value.stringValue ?? "" }, set: {
                    update(field, .string($0), output, record)
                })) {
                    ForEach(config.actions, id: \.name) { action in Text(humanize(action.name)).tag(action.name) }
                }
                .accessibilityIdentifier("setup.catalog.\(output.type).\(record.index).\(field.name)")
            }
        case "integer":
            integerField(field, value: numeric(value) ?? field.integer("default") ?? field.integer("min") ?? 0,
                         id: "setup.catalog.\(output.type).\(record.index).\(field.name)") {
                update(field, .number(Double($0)), output, record)
            }
        case "enum":
            let choices = field.stringArray("values") ?? []
            Picker(humanize(field.name), selection: Binding(get: { value.stringValue ?? choices.first ?? "" }, set: {
                update(field, .string($0), output, record)
            })) {
                ForEach(choices, id: \.self) { Text(humanize($0)).tag($0) }
            }
            .accessibilityIdentifier("setup.catalog.\(output.type).\(record.index).\(field.name)")
        case "rgb":
            let channels = value.object ?? [:]
            HStack {
                ForEach(["red", "green", "blue"], id: \.self) { channel in
                    integerField(channel, value: numeric(channels[channel]) ?? field.integer("min") ?? 0,
                                 id: "setup.catalog.\(output.type).\(record.index).\(field.name).\(channel)") { number in
                        var next = channels
                        next[channel] = .number(Double(number))
                        update(field, .object(next), output, record)
                    }
                }
            }
        case "zone":
            zoneEditor(field, output: output, record: record, value: value)
        default:
            VStack(alignment: .leading) {
                Text("Unsupported field: \(humanize(field.name))").themeLabel()
                rawJSON(value)
            }
        }
    }

    private func zoneEditor(_ field: OutputCatalog.Field, output: OutputCatalog.Output,
                            record: BindingRecord, value: JSONValue) -> some View {
        let zone = value.object ?? [:]
        let start = numeric(zone["start"]) ?? 0
        let length = numeric(zone["length"]) ?? 1
        let directions = field.stringArray("directions") ?? []
        let direction = zone["direction"]?.stringValue ?? directions.first ?? ""
        let setting = field.string("pixels_setting")
        let settingDefault = setting.flatMap { name in
            catalog.sinks.first(where: { $0.sink == output.sink })?.settings.first(where: { $0.name == name })?.integer("default")
        }
        let configuredLimit = setting.flatMap { name in numeric(config.sinks[output.sink]?.object?[name]) } ?? settingDefault
        let maximum = min(field.integer("pixels") ?? 0, configuredLimit ?? Int.max)
        let exceeds = start < 0 || length < 1 || start.addingReportingOverflow(length).overflow || start + length > maximum
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                integerField("ZONE START", value: start, id: "setup.catalog.\(output.type).\(record.index).zone.start") { setZone("start", $0, zone, field, output, record) }
                integerField("LED COUNT", value: length, id: "setup.catalog.\(output.type).\(record.index).zone.length") { setZone("length", $0, zone, field, output, record) }
            }
            Picker("Direction", selection: Binding(get: { direction }, set: {
                setZone("direction", $0, zone, field, output, record)
            })) {
                ForEach(directions, id: \.self) { Text(humanize($0)).tag($0) }
            }
            if exceeds {
                Text("This zone exceeds the current \(setting.map(humanize) ?? "pixel") limit of \(maximum). The controller checks this when you send.")
                    .font(.caption).foregroundStyle(Theme.Colors.signalYellow)
                    .accessibilityIdentifier("setup.catalog.\(output.type).\(record.index).zone.warning")
            }
        }
    }

    private func setZone(_ key: String, _ value: Int, _ zone: [String: JSONValue],
                         _ field: OutputCatalog.Field, _ output: OutputCatalog.Output, _ record: BindingRecord) {
        setZone(key, .number(Double(value)), zone, field, output, record)
    }

    private func setZone(_ key: String, _ value: String, _ zone: [String: JSONValue],
                         _ field: OutputCatalog.Field, _ output: OutputCatalog.Output, _ record: BindingRecord) {
        setZone(key, .string(value), zone, field, output, record)
    }

    private func setZone(_ key: String, _ value: JSONValue, _ zone: [String: JSONValue],
                         _ field: OutputCatalog.Field, _ output: OutputCatalog.Output, _ record: BindingRecord) {
        var next = zone
        next[key] = value
        update(field, .object(next), output, record)
    }

    private func update(_ field: OutputCatalog.Field, _ value: JSONValue,
                        _ output: OutputCatalog.Output, _ record: BindingRecord) {
        selection.setCatalogField(field.name, value: value, outputType: output.type, outputIndex: record.index)
    }

    private func bindingIsEditable(_ record: BindingRecord, for output: OutputCatalog.Output) -> Bool {
        Self.bindingIsEditable(record.value, for: output)
    }

    static func isEditable(_ binding: ControllerConfig.OutputBinding, in catalog: OutputCatalog) -> Bool {
        guard let value = jsonValue(binding),
              let type = value.object?["type"]?.stringValue,
              let output = catalog.outputs.first(where: { $0.type == type }),
              output.isEditable else { return false }
        return bindingIsEditable(value, for: output)
    }

    private static func bindingIsEditable(_ value: JSONValue, for output: OutputCatalog.Output) -> Bool {
        for field in output.fields {
            guard let value = value.object?[field.name] else { continue }
            if field.kind == "enum", let item = value.stringValue,
               !(field.stringArray("values") ?? []).contains(item) { return false }
            if field.kind == "zone", let direction = value.object?["direction"]?.stringValue,
               !(field.stringArray("directions") ?? []).contains(direction) { return false }
        }
        return true
    }

    private func integerField(_ field: OutputCatalog.Field, value: Int, id: String,
                              onChange: @escaping (Int) -> Void) -> some View {
        integerField(humanize(field.name), value: value, id: id, onChange: onChange)
    }

    private func integerField(_ label: String, value: Int, id: String,
                              onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label.uppercased()).themeLabel()
            Spacer()
            CatalogIntegerField(label: label, value: value, id: id, onChange: onChange)
        }
    }

    private func stringField(_ label: String, value: String, onChange: @escaping (String) -> Void) -> some View {
        TextField(humanize(label), text: Binding(get: { value }, set: onChange))
            .textInputAutocapitalization(.never)
            .accessibilityLabel(humanize(label))
    }

    private func sinkValue(_ sink: String, _ field: OutputCatalog.Field) -> Int {
        numeric(config.sinks[sink]?.object?[field.name]) ?? field.integer("default") ?? field.integer("min") ?? 0
    }

    private func defaultValue(_ field: OutputCatalog.Field) -> JSONValue {
        switch field.kind {
        case "action": .string("")
        case "integer": .number(Double(field.integer("default") ?? field.integer("min") ?? 0))
        case "enum": .string(field.stringArray("values")?.first ?? "")
        case "rgb": .object(["red": .number(0), "green": .number(0), "blue": .number(0)])
        case "zone": .object(["start": .number(0), "length": .number(1), "direction": .string(field.stringArray("directions")?.first ?? "")])
        default: .null
        }
    }

    private func numeric(_ value: JSONValue?) -> Int? {
        value?.integerValue
    }

    private func rawJSON(_ value: JSONValue) -> some View {
        Text(String(data: (try? JSONEncoder().encode(value)) ?? Data("null".utf8), encoding: .utf8) ?? "null")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Theme.Colors.textSecondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func jsonValue(_ binding: ControllerConfig.OutputBinding) -> JSONValue? {
        if case .unknown(let json) = binding { return json }
        guard let data = try? JSONEncoder().encode(binding) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func humanize(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct BindingRecord: Identifiable {
    let index: Int
    let type: String
    let action: String
    let value: JSONValue
    var id: Int { index }
}

private struct CatalogIntegerField: View {
    let label: String
    let value: Int
    let id: String
    let onChange: (Int) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(label: String, value: Int, id: String, onChange: @escaping (Int) -> Void) {
        self.label = label
        self.value = value
        self.id = id
        self.onChange = onChange
        _text = State(initialValue: String(value))
    }

    var body: some View {
        TextField(label, text: $text)
            .font(Theme.Typography.value)
            .multilineTextAlignment(.trailing)
            .keyboardType(.numbersAndPunctuation)
            .submitLabel(.done)
            .focused($focused)
            .onChange(of: text) { _, value in if let integer = Int(value) { onChange(integer) } }
            .onChange(of: self.value) { _, value in if !focused { text = String(value) } }
            .frame(width: 84)
            .padding(Theme.Spacing.xs)
            .background(Theme.Colors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(Theme.Colors.separator, lineWidth: 1))
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }
}
