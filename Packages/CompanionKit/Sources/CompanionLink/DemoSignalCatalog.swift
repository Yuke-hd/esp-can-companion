import Foundation
import CompanionProtocol

/// Synthetic metadata and values, serialized through the production decoders' bounds.
/// Handles are fixture-local; semantic keys and choice keys remain authoritative.
public struct DemoSignalCatalog: Sendable {
    public struct Entry: Sendable {
        public let handle: UInt16
        public let key: String
        public let type: SignalType
        public let unit: String
        public let evidence: String
        public let choices: [String]

        public init(handle: UInt16, key: String, type: SignalType, unit: String = "none",
                    evidence: String = "reference", choices: [String] = []) {
            self.handle = handle
            self.key = key
            self.type = type
            self.unit = unit
            self.evidence = evidence
            self.choices = choices
        }
    }

    public let document: Data
    public let catalog: SignalCatalog

    public init(token: UInt32, entries: [Entry]) throws {
        guard entries.count <= SignalCatalog.maximumSignals else { throw Self.invalidFixture() }
        var document = Data([1])
        Self.append(UInt16(entries.count), to: &document)
        for entry in entries {
            guard entry.choices.count <= SignalCatalog.maximumChoices,
                  entry.choices.allSatisfy({ (1...63).contains($0.utf8.count) }),
                  (1...63).contains(entry.key.utf8.count),
                  (1...31).contains(entry.unit.utf8.count),
                  (1...31).contains(entry.evidence.utf8.count),
                  entry.type == .enumeration || entry.choices.isEmpty else { throw Self.invalidFixture() }
            var body = Data()
            Self.append(entry.handle, to: &body)
            Self.tlv(1, Data(entry.key.utf8), to: &body)
            Self.tlv(2, Data([entry.type.rawValue]), to: &body)
            Self.tlv(3, Data(entry.unit.utf8), to: &body)
            Self.tlv(4, Data(entry.evidence.utf8), to: &body)
            if entry.type == .enumeration {
                var choices = Data()
                Self.append(UInt16(entry.choices.count), to: &choices)
                for (index, key) in entry.choices.enumerated() {
                    Self.append(UInt16(index + 1), to: &choices)
                    choices.append(UInt8(key.utf8.count))
                    choices.append(contentsOf: key.utf8)
                }
                Self.tlv(5, choices, to: &body)
            }
            Self.append(UInt16(body.count), to: &document)
            document.append(body)
        }
        catalog = try SignalCatalog(decoding: document, token: token)
        self.document = document
    }

    /// Pack complete records into independently parseable notifications. Missing,
    /// wrong-type and unencodable values retain availability without a value.
    public func packets(sequence: UInt16, started: Bool = true,
                        readings: [String: SignalReading<ExtensibleSignalValue>],
                        maximumBytes: Int = ExtensibleLiveSignalPacket.maximumBytes) throws -> [Data] {
        guard (13...ExtensibleLiveSignalPacket.maximumBytes).contains(maximumBytes) else { throw Self.invalidFixture() }
        var packets: [Data] = []
        func header(_ sequence: UInt16) -> Data {
            var data = Data([1])
            Self.append(sequence, to: &data)
            data.append(started ? 1 : 0)
            Self.append(catalog.token, to: &data)
            return data
        }
        var packet = header(sequence)
        for descriptor in catalog.descriptors {
            let reading = readings[descriptor.key] ?? .unknown
            var status = Self.status(reading.availability)
            if descriptor.key == "vehicle.brake_pressed", status == 1 { status = 3 }
            var value = Data()
            switch (descriptor.type.known, reading.value) {
            case (.boolean, .boolean(let boolean)): value.append(boolean ? 1 : 0)
            case (.number, .number(let number)) where number.isFinite: Self.append(number.bitPattern, to: &value)
            case (.enumeration, .enumeration(let key)):
                if let choice = descriptor.choices.first(where: { $0.key == key }) { Self.append(choice.handle, to: &value) }
            default: break
            }
            if !value.isEmpty { status |= 8 }
            var record = Data([UInt8(4 + value.count)])
            Self.append(descriptor.handle, to: &record)
            record.append(contentsOf: [descriptor.type.rawValue, status])
            record.append(value)
            guard record.count + 8 <= maximumBytes else { throw Self.invalidFixture() }
            if packet.count + record.count > maximumBytes {
                packets.append(packet)
                packet = header(sequence &+ UInt16(packets.count))
            }
            packet.append(record)
        }
        packets.append(packet)
        for packet in packets { _ = try ExtensibleLiveSignalPacket(decoding: packet) }
        return packets
    }

    static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        for shift in stride(from: 0, to: T.bitWidth, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }

    private static func tlv(_ tag: UInt8, _ value: Data, to data: inout Data) {
        data.append(tag)
        append(UInt16(value.count), to: &data)
        data.append(value)
    }

    private static func status(_ availability: SignalAvailability) -> UInt8 {
        switch availability {
        case .noData: return 0
        case .fresh: return 1
        case .stale: return 2
        case .freshnessUnverified: return 3
        case .unavailable: return 4
        case .readFailed: return 5
        case .notSupported: return 6
        case .unknown: return 7
        }
    }

    private static func invalidFixture() -> ProtocolDecodingError { .invalidValue(field: "demo_fixture") }

    // Keys and choices match firmware Mazda catalog metadata. Order/handles are
    // deliberately the demo's own; they are not provider ids or raw enum values.
    public static let vehicle: DemoSignalCatalog = {
        let rows: [(String, SignalType, String, [String])] = [
            ("vehicle.engine_rpm", .number, "rpm", []),
            ("vehicle.speed_kph", .number, "km/h", []),
            ("vehicle.turn_state", .enumeration, "none", ["unknown", "off", "left", "right", "hazard"]),
            ("vehicle.selector_position", .enumeration, "none", ["unknown", "shifting", "park", "reverse", "neutral", "drive"]),
            ("vehicle.actual_gear", .enumeration, "none", ["unknown", "park_or_neutral", "park", "neutral", "reverse", "first", "second", "third", "fourth", "fifth", "sixth", "shifting"]),
            ("vehicle.wiper.front_position", .enumeration, "none", ["unknown", "off", "on", "high", "intermittent"]),
            ("vehicle.hazard_request", .boolean, "none", []),
            ("vehicle.turn_request.left", .boolean, "none", []),
            ("vehicle.turn_request.right", .boolean, "none", []),
            ("vehicle.indicator_lamp.left", .boolean, "none", []),
            ("vehicle.indicator_lamp.right", .boolean, "none", []),
            ("vehicle.liftgate_open", .boolean, "none", []),
            ("vehicle.door.rear_right", .boolean, "none", []),
            ("vehicle.door.rear_left", .boolean, "none", []),
            ("vehicle.door.front_left_rhd", .boolean, "none", []),
            ("vehicle.door.front_right_rhd", .boolean, "none", []),
            ("vehicle.doors_unlocked", .boolean, "none", []),
            ("vehicle.wiper.low", .boolean, "none", []),
            ("vehicle.brake_pressed", .boolean, "none", []),
            ("vehicle.acceleration.longitudinal", .number, "m/s^2", []),
            ("vehicle.acceleration.lateral", .number, "m/s^2", []),
        ]
        // Static fixture mistakes must fail during development, never truncate.
        return try! DemoSignalCatalog(token: 0x44454D4F, entries: rows.enumerated().map { index, row in
            Entry(handle: UInt16(index + 1), key: row.0, type: row.1, unit: row.2, choices: row.3)
        })
    }()
}
