import Foundation

/// A write to the Config characteristic.
public enum ConfigWritePDU: Equatable, Sendable {
    /// Opens a transfer of `totalLength` bytes whose CRC-32 is `crc32`.
    case start(totalLength: UInt16, crc32: UInt32)
    /// Appends `data` at `offset`. Chunks must arrive in order and without gaps.
    case chunk(offset: UInt16, data: Data)
    case commit
    /// Discards an open transfer; harmless when none is open.
    case abort
    /// Sets the page offset for later Config reads on this connection.
    case selectReadPage(offset: UInt16)

    /// Bytes in a Chunk PDU before its data.
    public static let chunkHeaderLength = 3

    public var encoded: Data {
        var data = Data()
        switch self {
        case .start(let totalLength, let crc32):
            data.append(0x01)
            data.appendLittleEndian(totalLength)
            data.appendLittleEndian(crc32)
        case .chunk(let offset, let payload):
            data.append(0x02)
            data.appendLittleEndian(offset)
            data.append(payload)
        case .commit:
            data.append(0x03)
        case .abort:
            data.append(0x04)
        case .selectReadPage(let offset):
            data.append(0x05)
            data.appendLittleEndian(offset)
        }
        return data
    }
}

/// Which config the controller selected at boot.
public enum ConfigSourceCode: UInt8, Equatable, Sendable {
    case factory = 0
    case persistedOverride = 1
    /// The controller selected no config during this boot.
    case none = 0xFF
}

public typealias ConfigSource = WireValue<ConfigSourceCode>

/// One page of the active config's canonical JSON, as a Config read returns it.
public struct ConfigReadPage: Equatable, Sendable {
    public static let maximumDataLength = 200

    public var source: ConfigSource
    /// Length of the whole document.
    public var totalLength: UInt16
    /// CRC-32 of the whole document.
    public var crc32: UInt32
    public var pageOffset: UInt16
    public var data: Data

    public init(source: ConfigSource, totalLength: UInt16, crc32: UInt32, pageOffset: UInt16, data: Data) {
        self.source = source
        self.totalLength = totalLength
        self.crc32 = crc32
        self.pageOffset = pageOffset
        self.data = data
    }

    public init(decoding value: Data) throws {
        var reader = ByteReader(value)
        source = ConfigSource(rawValue: try reader.u8("source"))
        totalLength = try reader.u16("total_length")
        crc32 = try reader.u32("crc32")
        pageOffset = try reader.u16("page_offset")
        guard pageOffset <= totalLength else {
            throw ProtocolDecodingError.invalidValue(field: "page_offset")
        }
        let expected = min(Int(totalLength) - Int(pageOffset), Self.maximumDataLength)
        guard reader.remaining == expected else {
            throw reader.remaining < expected
                ? ProtocolDecodingError.truncated(field: "data")
                : ProtocolDecodingError.invalidValue(field: "data")
        }
        data = try reader.bytes(expected, "data")
    }
}

/// The active config as read back from the controller.
public struct ConfigReadBack: Equatable, Sendable {
    public var source: ConfigSource
    /// Canonical JSON produced by the controller. Empty when `source` is `none`.
    public var document: Data
    public var crc32: UInt32

    public init(source: ConfigSource, document: Data, crc32: UInt32) {
        self.source = source
        self.document = document
        self.crc32 = crc32
    }

    /// Decodes the document as a schema version 1 config. Call this only when
    /// device info reports a supported schema; otherwise show the JSON as opaque text.
    public func decodeConfig() throws -> ControllerConfig {
        try ControllerConfig(canonicalJSON: document)
    }
}
