import Foundation

/// A JSON value retained verbatim in meaning when the client does not know
/// the field's schema.
public indirect enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    /// Integers beyond Double's consecutive integer range retain their exact JSON value.
    case integer(Int64)
    case unsignedInteger(UInt64)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: JSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
        } else if var container = try? decoder.unkeyedContainer() {
            var values: [JSONValue] = []
            while !container.isAtEnd { values.append(try container.decode(JSONValue.self)) }
            self = .array(values)
        } else {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Int64.self), !(-9_007_199_254_740_991...9_007_199_254_740_991).contains(value) {
                self = .integer(value)
            } else if let value = try? container.decode(UInt64.self), value > 9_007_199_254_740_991 {
                self = .unsignedInteger(value)
            } else if let value = try? container.decode(Double.self) { self = .number(value) }
            else { self = .string(try container.decode(String.self)) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in object {
                try container.encode(value, forKey: DynamicCodingKey(key))
            }
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .integer(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .unsignedInteger(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    /// Returns a representable integer without trapping on rounded floating-point bounds.
    public var integerValue: Int? {
        switch self {
        case .number(let value): Int(exactly: value)
        case .integer(let value): Int(exactly: value)
        case .unsignedInteger(let value): Int(exactly: value)
        default: nil
        }
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var object: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
