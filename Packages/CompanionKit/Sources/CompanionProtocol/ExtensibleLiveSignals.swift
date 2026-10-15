import Foundation

/// A bounded, completely framed notification. Semantic errors are interpreted
/// against the catalog by the feed; framing errors reject the whole packet.
public struct ExtensibleLiveSignalPacket: Equatable, Sendable {
    public static let maximumBytes = 244
    public let sequence: UInt16
    public let isTelemetryStarted: Bool
    public let token: UInt32
    public let records: [ExtensibleLiveSignalRecord]

    public init(decoding data: Data) throws {
        guard (8...Self.maximumBytes).contains(data.count) else {
            throw ProtocolDecodingError.invalidValue(field: "extensible_packet_length")
        }
        var reader = ByteReader(data)
        guard try reader.u8("format") == 1 else {
            throw ProtocolDecodingError.invalidValue(field: "extensible_format")
        }
        sequence = try reader.u16("sequence")
        isTelemetryStarted = try reader.u8("flags") & 1 != 0
        token = try reader.u32("catalog_token")
        var decoded: [ExtensibleLiveSignalRecord] = []
        var handles = Set<UInt16>()
        while reader.remaining > 0 {
            let length = Int(try reader.u8("record_length"))
            guard length >= 4 else { throw ProtocolDecodingError.invalidValue(field: "record_length") }
            var record = ByteReader(try reader.bytes(length, "record"))
            let handle = try record.u16("handle")
            guard handles.insert(handle).inserted else {
                throw ProtocolDecodingError.invalidValue(field: "duplicate_handle")
            }
            let type = try record.u8("type")
            let status = try record.u8("status")
            decoded.append(ExtensibleLiveSignalRecord(handle: handle, type: type, status: status,
                                                      value: try record.bytes(record.remaining, "value")))
        }
        records = decoded
    }
}

public struct ExtensibleLiveSignalRecord: Equatable, Sendable {
    public let handle: UInt16
    public let type: UInt8
    public let status: UInt8
    public let value: Data
}

public enum ExtensibleSignalValue: Equatable, Sendable {
    case boolean(Bool)
    case number(Float)
    /// Catalog choice key, rather than a provider enum ordinal.
    case enumeration(choiceKey: String)
}

extension ExtensibleLiveSignalRecord {
    func reading(for descriptor: SignalDescriptor) -> SignalReading<ExtensibleSignalValue> {
        guard type == descriptor.type.rawValue, let knownType = descriptor.type.known,
              status & 0xf0 == 0, status & 7 != 7 else { return .unknown }
        var availability = SignalAvailability(code: status)
        if descriptor.key == "vehicle.brake_pressed", availability == .fresh {
            availability = .freshnessUnverified
        }
        guard status & 8 != 0 else {
            return value.isEmpty ? SignalReading(availability: availability, value: nil) : .unknown
        }
        let decoded: ExtensibleSignalValue
        switch knownType {
        case .boolean:
            guard value.count == 1, let byte = value.first, byte <= 1 else { return .unknown }
            decoded = .boolean(byte == 1)
        case .number:
            guard value.count == 4 else { return .unknown }
            var reader = ByteReader(value)
            guard let bits = try? reader.u32("number") else { return .unknown }
            let number = Float(bitPattern: bits)
            guard number.isFinite else { return .unknown }
            decoded = .number(number)
        case .enumeration:
            guard value.count == 2 else { return .unknown }
            var reader = ByteReader(value)
            guard let handle = try? reader.u16("choice"),
                  let choice = descriptor.choices.first(where: { $0.handle == handle }) else { return .unknown }
            decoded = .enumeration(choiceKey: choice.key)
        }
        return SignalReading(availability: availability, value: decoded)
    }
}
