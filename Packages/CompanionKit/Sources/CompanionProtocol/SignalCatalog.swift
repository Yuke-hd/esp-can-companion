import Foundation

public enum SignalType: UInt8, Equatable, Sendable {
    case boolean = 1
    case number = 2
    case enumeration = 3
}

public struct SignalEnumChoice: Equatable, Sendable {
    public let handle: UInt16
    public let key: String
}

/// Metadata tokens retain their exact wire spelling, including unfamiliar tokens.
/// Unknown types are opaque: clients must not decode or expose their values.
public struct SignalDescriptor: Equatable, Sendable {
    public let handle: UInt16
    public let key: String
    public let type: WireValue<SignalType>
    public let unit: String
    public let evidence: String
    public let choices: [SignalEnumChoice]
}

/// A complete, validated mapping. Its handles are meaningful only for the
/// connection that discovered it; reconnecting requires a new complete download.
public struct SignalCatalog: Equatable, Sendable {
    public static let maximumDocumentBytes = 16 * 1024
    public static let maximumSignals = 64
    public static let maximumChoices = 32
    public let token: UInt32
    public let descriptors: [SignalDescriptor]

    public func descriptor(for handle: UInt16) -> SignalDescriptor? {
        descriptors.first { $0.handle == handle }
    }

    public init(decoding document: Data, token: UInt32) throws {
        guard token != 0, document.count <= Self.maximumDocumentBytes else {
            throw ProtocolDecodingError.invalidValue(field: "catalog")
        }
        var reader = ByteReader(document)
        guard try reader.u8("catalog_format") == 1 else {
            throw ProtocolDecodingError.invalidValue(field: "catalog_format")
        }
        let count = Int(try reader.u16("signal_count"))
        guard count <= Self.maximumSignals else {
            throw ProtocolDecodingError.invalidValue(field: "signal_count")
        }
        var decoded: [SignalDescriptor] = []
        var handles = Set<UInt16>()
        // UTF-8 byte identity avoids Swift String's canonical-equivalence folding.
        var keys = Set<Data>()
        for _ in 0..<count {
            let length = Int(try reader.u16("body_length"))
            let descriptor = try Self.decodeDescriptor(reader.bytes(length, "descriptor"))
            guard handles.insert(descriptor.handle).inserted,
                  keys.insert(Data(descriptor.key.utf8)).inserted else {
                throw ProtocolDecodingError.invalidValue(field: "descriptor_uniqueness")
            }
            decoded.append(descriptor)
        }
        guard reader.remaining == 0 else {
            throw ProtocolDecodingError.invalidValue(field: "catalog_trailing_bytes")
        }
        self.token = token
        descriptors = decoded
    }

    private static func decodeDescriptor(_ body: Data) throws -> SignalDescriptor {
        var reader = ByteReader(body)
        let handle = try reader.u16("handle")
        guard handle != 0 else { throw ProtocolDecodingError.invalidValue(field: "handle") }
        var fields: [UInt8: Data] = [:]
        while reader.remaining > 0 {
            let tag = try reader.u8("tag")
            let length = Int(try reader.u16("tlv_length"))
            guard fields[tag] == nil else { throw ProtocolDecodingError.invalidValue(field: "duplicate_tag") }
            fields[tag] = try reader.bytes(length, "tlv_value")
        }
        func mandatory(_ tag: UInt8) throws -> Data {
            guard let value = fields[tag] else { throw ProtocolDecodingError.invalidValue(field: "mandatory_tag") }
            return value
        }
        let key = try string(mandatory(1), maximum: 63, field: "key")
        let typeBytes = try mandatory(2)
        guard typeBytes.count == 1 else { throw ProtocolDecodingError.invalidValue(field: "type") }
        let type = WireValue<SignalType>(rawValue: typeBytes[typeBytes.startIndex])
        let unit = try string(mandatory(3), maximum: 31, field: "unit")
        let evidence = try string(mandatory(4), maximum: 31, field: "evidence")
        if type.known == .boolean || type.known == .enumeration {
            guard unit == "none" else { throw ProtocolDecodingError.invalidValue(field: "unit") }
        }
        if type.known == .boolean || type.known == .number {
            guard fields[5] == nil else { throw ProtocolDecodingError.invalidValue(field: "choices") }
        }
        if type.known == .enumeration && fields[5] == nil {
            throw ProtocolDecodingError.invalidValue(field: "choices")
        }
        let choices = try fields[5].map(decodeChoices) ?? []
        return SignalDescriptor(handle: handle, key: key, type: type, unit: unit, evidence: evidence, choices: choices)
    }

    private static func string(_ data: Data, maximum: Int, field: String) throws -> String {
        guard !data.isEmpty, data.count <= maximum, let string = String(data: data, encoding: .utf8) else {
            throw ProtocolDecodingError.invalidValue(field: field)
        }
        return string
    }

    private static func decodeChoices(_ data: Data) throws -> [SignalEnumChoice] {
        var reader = ByteReader(data)
        let count = Int(try reader.u16("choice_count"))
        guard (1...maximumChoices).contains(count) else {
            throw ProtocolDecodingError.invalidValue(field: "choice_count")
        }
        var choices: [SignalEnumChoice] = []
        var handles = Set<UInt16>()
        var keys = Set<Data>()
        for _ in 0..<count {
            let handle = try reader.u16("choice_handle")
            let length = Int(try reader.u8("choice_key_length"))
            let raw = try reader.bytes(length, "choice_key")
            let key = try string(raw, maximum: 63, field: "choice_key")
            guard handle != 0, handles.insert(handle).inserted, keys.insert(raw).inserted else {
                throw ProtocolDecodingError.invalidValue(field: "choice_uniqueness")
            }
            choices.append(SignalEnumChoice(handle: handle, key: key))
        }
        guard reader.remaining == 0 else { throw ProtocolDecodingError.invalidValue(field: "choices") }
        return choices
    }
}

/// A selected catalog page, independent of Config transfer state. The discovery
/// client must additionally verify token, stable total size and requested offset.
public struct SignalCatalogPage: Equatable, Sendable {
    public static let maximumDataLength = 200
    public let token: UInt32
    public let totalBytes: UInt16
    public let offset: UInt16
    public let data: Data

    public init(decoding value: Data) throws {
        var reader = ByteReader(value)
        guard try reader.u8("catalog_format") == 1 else {
            throw ProtocolDecodingError.invalidValue(field: "catalog_format")
        }
        token = try reader.u32("catalog_token")
        totalBytes = try reader.u16("total_bytes")
        offset = try reader.u16("offset")
        let length = Int(try reader.u16("data_length"))
        guard token != 0, (3...SignalCatalog.maximumDocumentBytes).contains(Int(totalBytes)),
              offset <= totalBytes, length <= Self.maximumDataLength,
              Int(offset) + length <= Int(totalBytes),
              length > 0 || offset == totalBytes,
              reader.remaining == length else {
            throw ProtocolDecodingError.invalidValue(field: "catalog_page")
        }
        data = try reader.bytes(length, "page_data")
    }
}

public struct SignalCatalogSelector: Equatable, Sendable {
    public let token: UInt32
    public let offset: UInt16

    public init(token: UInt32, offset: UInt16) throws {
        guard token != 0, Int(offset) <= SignalCatalog.maximumDocumentBytes else {
            throw ProtocolDecodingError.invalidValue(field: "catalog_selector")
        }
        self.token = token
        self.offset = offset
    }

    public init(decoding value: Data) throws {
        guard value.count == 7 else { throw ProtocolDecodingError.invalidValue(field: "catalog_selector") }
        var reader = ByteReader(value)
        guard try reader.u8("catalog_format") == 1 else {
            throw ProtocolDecodingError.invalidValue(field: "catalog_format")
        }
        try self.init(token: reader.u32("catalog_token"), offset: reader.u16("offset"))
    }

    public var encoded: Data {
        var value = Data([1])
        value.appendLittleEndian(token)
        value.appendLittleEndian(offset)
        return value
    }
}
