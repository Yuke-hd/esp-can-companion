import XCTest
@testable import CompanionProtocol

/// Decodes and encodes the vendored golden vectors in `Fixtures/golden-vectors`.
/// See the README there for where each file comes from.
final class GoldenVectorTests: XCTestCase {
    // MARK: Fixture shapes

    struct Vectors<Vector: Decodable>: Decodable {
        var vectors: [Vector]
        var invalid: [Invalid]?
    }

    struct Invalid: Decodable {
        var name: String
        var hex: String
        var error: [String: String]

        var expected: ProtocolDecodingError {
            if let field = error["truncated"] { return .truncated(field: field) }
            return .invalidValue(field: error["invalid"] ?? "?")
        }
    }

    // MARK: CRC

    func testCRC32Vectors() throws {
        struct Vector: Decodable { var name: String; var ascii: String; var crc32: UInt32 }
        for vector in try Fixtures.load(Vectors<Vector>.self, "crc32.json").vectors {
            XCTAssertEqual(CRC32.checksum(Data(vector.ascii.utf8)), vector.crc32, vector.name)
        }
    }

    // MARK: Device info

    func testDeviceInfoVectors() throws {
        struct Fields: Decodable, Equatable {
            var protocolMajor: UInt8, protocolMinor: UInt8, configSchemaVersion: UInt16
            var liveSignalLayoutVersion: UInt8, flags: UInt8, maxConfigBytes: UInt16
            var firmwareVersion: String, hardwareId: String
        }
        struct Vector: Decodable { var name: String; var hex: String; var fields: Fields }
        let fixture = try Fixtures.load(Vectors<Vector>.self, "device-info.json")
        for vector in fixture.vectors {
            let info = try DeviceInfo(decoding: Fixtures.hex(vector.hex))
            let decoded = Fields(
                protocolMajor: info.protocolMajor, protocolMinor: info.protocolMinor,
                configSchemaVersion: info.configSchemaVersion, liveSignalLayoutVersion: info.liveSignalLayoutVersion,
                flags: info.flags, maxConfigBytes: info.maxConfigBytes,
                firmwareVersion: info.firmwareVersion, hardwareId: info.hardwareID
            )
            XCTAssertEqual(decoded, vector.fields, vector.name)
            XCTAssertEqual(info.isPairingWindowOpen, vector.fields.flags & 1 == 1, vector.name)
        }
        try assertInvalid(fixture.invalid) { try DeviceInfo(decoding: $0) }
    }

    // MARK: Config transfer

    func testConfigWritePDUVectors() throws {
        struct PDU: Decodable {
            struct Start: Decodable { var totalLength: UInt16; var crc32: UInt32 }
            struct Chunk: Decodable { var offset: UInt16; var dataHex: String }
            struct Offset: Decodable { var offset: UInt16 }
            var start: Start?, chunk: Chunk?, commit: [String: String]?, abort: [String: String]?
            var selectReadPage: Offset?
        }
        struct Vector: Decodable { var name: String; var hex: String; var pdu: PDU }
        for vector in try Fixtures.load(Vectors<Vector>.self, "config-pdus.json").vectors {
            let pdu: ConfigWritePDU
            if let start = vector.pdu.start {
                pdu = .start(totalLength: start.totalLength, crc32: start.crc32)
            } else if let chunk = vector.pdu.chunk {
                pdu = .chunk(offset: chunk.offset, data: try Fixtures.hex(chunk.dataHex))
            } else if vector.pdu.commit != nil {
                pdu = .commit
            } else if vector.pdu.abort != nil {
                pdu = .abort
            } else if let select = vector.pdu.selectReadPage {
                pdu = .selectReadPage(offset: select.offset)
            } else {
                return XCTFail("Unknown PDU in \(vector.name)")
            }
            XCTAssertEqual(pdu.encoded, try Fixtures.hex(vector.hex), vector.name)
        }
    }

    func testConfigReadPageVectors() throws {
        struct Fields: Decodable {
            var source: UInt8, totalLength: UInt16, crc32: UInt32, pageOffset: UInt16, dataHex: String
        }
        struct Vector: Decodable { var name: String; var hex: String; var fields: Fields }
        let fixture = try Fixtures.load(Vectors<Vector>.self, "config-read-page.json")
        for vector in fixture.vectors {
            let page = try ConfigReadPage(decoding: Fixtures.hex(vector.hex))
            let expected = ConfigReadPage(
                source: ConfigSource(rawValue: vector.fields.source),
                totalLength: vector.fields.totalLength,
                crc32: vector.fields.crc32,
                pageOffset: vector.fields.pageOffset,
                data: try Fixtures.hex(vector.fields.dataHex)
            )
            XCTAssertEqual(page, expected, vector.name)
        }
        try assertInvalid(fixture.invalid) { try ConfigReadPage(decoding: $0) }
    }

    func testConfigStatusVectors() throws {
        struct Fields: Decodable {
            var state: UInt8, result: UInt8, bootFlags: UInt8, activeSource: UInt8, activeLength: UInt16
            var activeCrc32: UInt32, transferLength: UInt16, receivedLength: UInt16
            var savedLength: UInt16, savedCrc32: UInt32
        }
        struct Rejection: Decodable {
            var category: UInt8, code: UInt8, validation: UInt8, index: UInt16, path: String, pathTruncated: Bool
        }
        struct Apply: Decodable {
            var stage: UInt8, validation: UInt8, section: UInt8, index: UInt16, binding: UInt8, engine: UInt8
        }
        struct Boot: Decodable { var code: UInt8, validation: UInt8 }
        struct Vector: Decodable {
            var name: String, hex: String, fields: Fields
            var rejection: Rejection?, applyRejection: Apply?, bootDiagnostic: Boot?
        }
        let fixture = try Fixtures.load(Vectors<Vector>.self, "config-status.json")
        for vector in fixture.vectors {
            let status = try ConfigStatus(decoding: Fixtures.hex(vector.hex))
            let fields = vector.fields
            XCTAssertEqual(status.state.rawValue, fields.state, vector.name)
            XCTAssertEqual(status.result.rawValue, fields.result, vector.name)
            XCTAssertEqual(status.bootFlags.rawValue, fields.bootFlags, vector.name)
            XCTAssertEqual(status.activeSource.rawValue, fields.activeSource, vector.name)
            XCTAssertEqual(status.activeLength, fields.activeLength, vector.name)
            XCTAssertEqual(status.activeCRC32, fields.activeCrc32, vector.name)
            XCTAssertEqual(status.transferLength, fields.transferLength, vector.name)
            XCTAssertEqual(status.receivedLength, fields.receivedLength, vector.name)
            XCTAssertEqual(status.savedLength, fields.savedLength, vector.name)
            XCTAssertEqual(status.savedCRC32, fields.savedCrc32, vector.name)

            XCTAssertEqual(status.rejection, vector.rejection.map {
                ConfigRejection(
                    category: WireValue(rawValue: $0.category), code: WireValue(rawValue: $0.code),
                    validation: WireValue(rawValue: $0.validation), index: $0.index,
                    path: $0.path, isPathTruncated: $0.pathTruncated
                )
            }, vector.name)
            XCTAssertEqual(status.applyRejection, vector.applyRejection.map {
                ApplyRejection(
                    stage: WireValue(rawValue: $0.stage), validation: WireValue(rawValue: $0.validation),
                    section: WireValue(rawValue: $0.section), index: $0.index,
                    binding: WireValue(rawValue: $0.binding), engine: WireValue(rawValue: $0.engine)
                )
            }, vector.name)
            XCTAssertEqual(status.bootDiagnostic, vector.bootDiagnostic.map {
                BootDiagnostic(code: WireValue(rawValue: $0.code), validation: WireValue(rawValue: $0.validation))
            }, vector.name)
        }
        try assertInvalid(fixture.invalid) { try ConfigStatus(decoding: $0) }
    }

    func testConfigStatusTypedCodes() throws {
        let fixture = try Fixtures.load(Vectors<NamedHex>.self, "config-status.json")
        let zone = try XCTUnwrap(fixture.vectors.first { $0.name == "config rejected: zone out of range" })
        let rejection = try XCTUnwrap(ConfigStatus(decoding: Fixtures.hex(zone.hex)).rejection)
        XCTAssertEqual(rejection.category, .known(.semantic))
        XCTAssertEqual(rejection.code, .known(.schemaValidation))
        XCTAssertEqual(rejection.validation, .known(.zoneOutOfRange))
        XCTAssertEqual(rejection.path, "outputs[3].zone.length")

        let newer = try XCTUnwrap(fixture.vectors.first { $0.name == "config rejected: codes from a newer firmware" })
        let unknown = try XCTUnwrap(ConfigStatus(decoding: Fixtures.hex(newer.hex)).rejection)
        XCTAssertEqual(unknown.validation, .unknown(99))
        XCTAssertEqual(unknown.validation.description, "unknown (99)")

        let apply = try XCTUnwrap(fixture.vectors.first { $0.name == "apply rejected: unknown signal in rule 2" })
        let applyRejection = try XCTUnwrap(ConfigStatus(decoding: Fixtures.hex(apply.hex)).applyRejection)
        XCTAssertEqual(applyRejection.stage, .known(.rule))
        XCTAssertEqual(applyRejection.section, .known(.rules))
        XCTAssertEqual(applyRejection.engine, .known(.unknownSignal))
    }

    // MARK: Command

    func testCommandVectors() throws {
        struct Vector: Decodable { var name: String; var opcode: UInt8; var hex: String }
        let vectors = try Fixtures.load(Vectors<Vector>.self, "command.json").vectors
        XCTAssertEqual(vectors.count, CompanionCommand.allCases.count)
        for vector in vectors {
            let command = try XCTUnwrap(CompanionCommand(rawValue: vector.opcode), vector.name)
            XCTAssertEqual(command.encoded, try Fixtures.hex(vector.hex), vector.name)
        }
    }

    // MARK: Live signals

    func testLiveSignalVectors() throws {
        struct Expected: Decodable { var availability: String; var value: JSONScalar? }
        struct Vector: Decodable {
            var name: String, hex: String, sequence: UInt8, telemetryStarted: Bool
            var signals: [String: Expected]

            enum CodingKeys: String, CodingKey {
                case name, hex, sequence, telemetryStarted = "telemetry_started", signals
            }
        }
        struct Fixture: Decodable { var signals: [String]; var vectors: [Vector]; var invalid: [Invalid] }
        // Signal names are dictionary keys, so no snake-case key conversion here.
        let fixture = try Fixtures.load(Fixture.self, "live-signals.json", convertingSnakeCase: false)
        XCTAssertEqual(fixture.signals.count, 19)
        for vector in fixture.vectors {
            let frame = try LiveSignalFrame(decoding: Fixtures.hex(vector.hex))
            XCTAssertEqual(frame.sequence, vector.sequence, vector.name)
            XCTAssertEqual(frame.isTelemetryStarted, vector.telemetryStarted, vector.name)
            let decoded = Self.readings(of: frame)
            XCTAssertEqual(decoded.map(\.name), fixture.signals)
            for (name, availability, value) in decoded {
                let expected = try XCTUnwrap(vector.signals[name], "\(vector.name): \(name)")
                XCTAssertEqual(availability, expected.availability, "\(vector.name): \(name)")
                XCTAssertEqual(value, expected.value, "\(vector.name): \(name)")
            }
        }
        try assertInvalid(fixture.invalid) { try LiveSignalFrame(decoding: $0) }
    }

    /// Each signal in signal-table order, with availability in fixture spelling.
    static func readings(of frame: LiveSignalFrame) -> [(name: String, availability: String, value: JSONScalar?)] {
        func entry<V>(_ name: String, _ reading: SignalReading<V>, _ value: (V) -> JSONScalar)
            -> (name: String, availability: String, value: JSONScalar?) {
            (name, availabilityName(reading.availability), reading.value.map(value))
        }
        func choice<K>(_ value: WireValue<K>) -> JSONScalar { .number(Double(value.rawValue)) }
        return [
            entry("engine_rpm", frame.engineRPM) { .number($0) },
            entry("speed_kph", frame.speedKPH) { .number($0) },
            entry("turn_state", frame.turnState, choice),
            entry("selector_position", frame.selectorPosition, choice),
            entry("actual_gear", frame.actualGear, choice),
            entry("front_wiper_position", frame.frontWiperPosition, choice),
            entry("hazard_request", frame.hazardRequest) { .bool($0) },
            entry("turn_request_left", frame.turnRequestLeft) { .bool($0) },
            entry("turn_request_right", frame.turnRequestRight) { .bool($0) },
            entry("indicator_lamp_left", frame.indicatorLampLeft) { .bool($0) },
            entry("indicator_lamp_right", frame.indicatorLampRight) { .bool($0) },
            entry("liftgate_open", frame.liftgateOpen) { .bool($0) },
            entry("door_rear_right", frame.doorRearRight) { .bool($0) },
            entry("door_rear_left", frame.doorRearLeft) { .bool($0) },
            entry("door_front_left_rhd", frame.doorFrontLeftRHD) { .bool($0) },
            entry("door_front_right_rhd", frame.doorFrontRightRHD) { .bool($0) },
            entry("doors_unlocked", frame.doorsUnlocked) { .bool($0) },
            entry("wiper_low", frame.wiperLow) { .bool($0) },
            entry("brake_pressed", frame.brakePressed) { .bool($0) },
        ]
    }

    static func availabilityName(_ availability: SignalAvailability) -> String {
        switch availability {
        case .noData: "no_data"
        case .fresh: "fresh"
        case .stale: "stale"
        case .freshnessUnverified: "freshness_unverified"
        case .unavailable: "unavailable"
        case .readFailed: "read_failed"
        case .notSupported: "not_supported"
        case .unknown: "unknown"
        }
    }

    // MARK: Config documents (vendored from the firmware)

    /// The firmware's canonical example documents decode, and re-encode to the
    /// same bytes, so the model keeps every field the controller serializes.
    func testCanonicalConfigDocumentsRoundTrip() throws {
        let documents = try Fixtures.configDocuments()
        XCTAssertFalse(documents.isEmpty)
        for (name, data) in documents {
            let config = try ControllerConfig(canonicalJSON: data)
            XCTAssertEqual(config.version, 1, name)
            let encoded = try config.encodedJSON()
            XCTAssertEqual(String(decoding: encoded, as: UTF8.self), String(decoding: data, as: UTF8.self), name)
        }
    }

    func testFactoryProfileDecodesToTypedModel() throws {
        let data = try XCTUnwrap(Fixtures.configDocuments()["controller-config-v1.json"])
        let config = try ControllerConfig(canonicalJSON: data)
        XCTAssertEqual(config.actions.map(\.name), ["left_turn", "right_turn", "hazard", "rpm_fill", "red_zone", "brake"])
        XCTAssertEqual(config.rules.last, .state(.init(
            action: "brake", signalKey: "vehicle.brake_pressed", comparison: .equal,
            operand: .boolean(true), freshness: .freshOrUnverified
        )))
        XCTAssertEqual(config.rules[3], .range(.init(
            action: "rpm_fill", signalKey: "vehicle.engine_rpm",
            input: .init(from: 0, to: 6500), output: .init(from: 0, to: 1), freshness: .freshOrUnverified
        )))
        XCTAssertEqual(config.outputs[5], .ledSolid(.init(
            action: "red_zone", zone: .init(start: 35, length: 30, direction: .startToEnd),
            color: .init(red: 16, green: 0, blue: 0), priority: 150
        )))
    }

    // MARK: Helpers

    struct NamedHex: Decodable { var name: String; var hex: String }

    private func assertInvalid<T>(
        _ vectors: [Invalid]?,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ decode: (Data) throws -> T
    ) throws {
        let vectors = try XCTUnwrap(vectors, file: file, line: line)
        XCTAssertFalse(vectors.isEmpty, file: file, line: line)
        for vector in vectors {
            XCTAssertThrowsError(try decode(Fixtures.hex(vector.hex)), vector.name, file: file, line: line) { error in
                XCTAssertEqual(error as? ProtocolDecodingError, vector.expected, vector.name, file: file, line: line)
            }
        }
    }
}

/// A JSON scalar from a fixture, compared with decoded values.
enum JSONScalar: Decodable, Equatable {
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }
}

enum Fixtures {
    static var directory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures/golden-vectors", isDirectory: true)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String, convertingSnakeCase: Bool = true) throws -> T {
        let decoder = JSONDecoder()
        if convertingSnakeCase { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        return try decoder.decode(type, from: Data(contentsOf: directory.appendingPathComponent(name)))
    }

    /// The vendored firmware config documents, without their trailing newline.
    static func configDocuments() throws -> [String: Data] {
        let folder = directory.appendingPathComponent("config-documents", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }
        return try Dictionary(uniqueKeysWithValues: names.map { name in
            var data = try Data(contentsOf: folder.appendingPathComponent(name))
            while data.last == UInt8(ascii: "\n") { data.removeLast() }
            return (name, data)
        })
    }

    static func hex(_ string: String) throws -> Data {
        guard string.count % 2 == 0 else { throw ProtocolDecodingError.invalidValue(field: "hex") }
        var data = Data()
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else {
                throw ProtocolDecodingError.invalidValue(field: "hex")
            }
            data.append(byte)
            index = next
        }
        return data
    }
}
