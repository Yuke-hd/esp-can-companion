import Foundation

/// The firmware's JSON description of editable outputs and sink settings.
public struct OutputCatalog: Equatable, Sendable {
    public let outputs: [Output]
    public let sinks: [Sink]

    public init(decoding document: Data) throws {
        do {
            guard let object = try JSONSerialization.jsonObject(with: document) as? [String: Any],
                  object["outputs"] is [[String: Any]] else {
                throw ProtocolDecodingError.invalidValue(field: "output_catalog")
            }
            let decoded = try JSONDecoder().decode(Document.self, from: document)
            var types = Set<String>()
            guard decoded.outputs.allSatisfy({ types.insert($0.type).inserted }) else {
                throw ProtocolDecodingError.invalidValue(field: "output_catalog_duplicate_type")
            }
            self.outputs = decoded.outputs
            self.sinks = decoded.sinks ?? []
        } catch let error as ProtocolDecodingError {
            throw error
        } catch {
            throw ProtocolDecodingError.invalidValue(field: "output_catalog")
        }
    }

    public struct Document: Decodable {
        let outputs: [Output]
        let sinks: [Sink]?
    }

    public struct Output: Decodable, Equatable, Sendable {
        public let type: String
        public let sink: String
        public let ruleTypes: [String]?
        public let fields: [Field]

        enum CodingKeys: String, CodingKey { case type, sink, ruleTypes = "rule_types", fields }
        public var isEditable: Bool { !fields.isEmpty && fields.allSatisfy(\.isEditable) }
    }

    public struct Sink: Decodable, Equatable, Sendable {
        public let sink: String
        public let settings: [Field]
    }

    public struct Field: Codable, Equatable, Sendable {
        public let name: String
        public let kind: String
        public let required: Bool
        /// Attributes beyond the common name/kind/required keys.
        public let attributes: [String: JSONValue]

        public init(from decoder: Decoder) throws {
            let object = try JSONValue(from: decoder).object ?? [:]
            guard let name = object["name"]?.stringValue,
                  let kind = object["kind"]?.stringValue,
                  case .bool(let required)? = object["required"] else {
                throw ProtocolDecodingError.invalidValue(field: "output_catalog_field")
            }
            self.name = name
            self.kind = kind
            self.required = required
            self.attributes = object.filter { !["name", "kind", "required"].contains($0.key) }
        }

        public func encode(to encoder: Encoder) throws {
            var object = attributes
            object["name"] = .string(name)
            object["kind"] = .string(kind)
            object["required"] = .bool(required)
            try JSONValue.object(object).encode(to: encoder)
        }

        public var isEditable: Bool {
            switch kind {
            case "action": true
            case "integer": integer("min") != nil && integer("max") != nil
            case "enum": stringArray("values")?.isEmpty == false
            case "rgb": integer("min") != nil && integer("max") != nil
            case "zone": integer("pixels") != nil && stringArray("directions")?.isEmpty == false
            default: false
            }
        }

        public func integer(_ key: String) -> Int? {
            attributes[key]?.integerValue
        }

        public func string(_ key: String) -> String? { attributes[key]?.stringValue }

        public func stringArray(_ key: String) -> [String]? {
            guard case .array(let values)? = attributes[key] else { return nil }
            let strings = values.compactMap(\.stringValue)
            return strings.count == values.count ? strings : nil
        }
    }
}

public extension DeviceInfo {
    /// Output catalog support is protocol 1.2 capability bit 1. The extension
    /// version is deliberately not part of this check.
    var supportsOutputCatalog: Bool {
        protocolMajor == 1 && protocolMinor >= 2 && (extensionFlags.map { $0 & 0x02 != 0 } ?? false)
    }
}
