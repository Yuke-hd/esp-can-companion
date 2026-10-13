import Foundation
import CompanionProtocol

/// Read-only presentation of the current catalog. Metadata retains its wire
/// spelling: unfamiliar tokens never imply a conversion or verified evidence.
public struct SignalReadout: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let key: String
        public let type: String
        public let value: String?
        public let status: PitWallReadout.Freshness
        public let unit: String
        public let evidence: String
        public let choices: [String]

        /// Swift String equality folds canonical equivalents; wire keys do not.
        public var id: Data { Data(key.utf8) }
        public var accessibilityIdentifier: String {
            "signals.row." + id.map { String(format: "%02x", $0) }.joined()
        }
        public var accessibilityText: String {
            var parts = [key, type, value ?? "no value", status.title,
                         "Unit token: \(unit)", "Evidence token: \(evidence)"]
            if !choices.isEmpty { parts.append("Choices: " + choices.joined(separator: ", ")) }
            return parts.joined(separator: ", ")
        }

        init(state: ExtensibleSignalState, stalled: Bool) {
            let descriptor = state.descriptor
            key = descriptor.key
            unit = descriptor.unit
            evidence = descriptor.evidence
            choices = descriptor.type.known == .enumeration ? descriptor.choices.map(\.key) : []
            let availability = stalled || descriptor.type.known == nil ? SignalAvailability.unknown : state.reading.availability
            status = PitWallReadout.Freshness(availability)
            switch descriptor.type.known {
            case .boolean: type = "Boolean"
            case .number: type = "Number"
            case .enumeration: type = "Enum"
            case nil: type = "Unsupported type (\(descriptor.type.rawValue))"
            }
            guard status.showsValue else { value = nil; return }
            switch (descriptor.type.known, state.reading.value) {
            case (.boolean, .boolean(let boolean)): value = boolean ? "True" : "False"
            case (.number, .number(let number)) where number.isFinite: value = String(number)
            case (.enumeration, .enumeration(let choice)) where choices.contains(where: { $0.utf8.elementsEqual(choice.utf8) }):
                value = choice
            default: value = nil
            }
        }
    }

    public let rows: [Row]

    public init(snapshot: ExtensibleSignalSnapshot?) {
        guard let snapshot, snapshot.catalog != nil else { rows = []; return }
        rows = snapshot.signals.map { Row(state: $0, stalled: snapshot.isStalled) }
            .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
    }
}
