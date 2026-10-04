import Foundation

/// A payload did not match the wire format.
public enum ProtocolDecodingError: Error, Equatable, Sendable {
    /// The payload ended before `field` could be read.
    case truncated(field: String)
    /// `field` held a value the spec does not allow.
    case invalidValue(field: String)
}

/// Reads little-endian fields from a payload, front to back.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    var remaining: Int { bytes.count - offset }

    mutating func u8(_ field: String) throws -> UInt8 {
        guard remaining >= 1 else { throw ProtocolDecodingError.truncated(field: field) }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u16(_ field: String) throws -> UInt16 {
        guard remaining >= 2 else { throw ProtocolDecodingError.truncated(field: field) }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    mutating func u32(_ field: String) throws -> UInt32 {
        guard remaining >= 4 else { throw ProtocolDecodingError.truncated(field: field) }
        defer { offset += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }

    mutating func bytes(_ count: Int, _ field: String) throws -> Data {
        guard count >= 0, remaining >= count else { throw ProtocolDecodingError.truncated(field: field) }
        defer { offset += count }
        return Data(bytes[offset..<offset + count])
    }

    /// A one-byte length followed by that many UTF-8 bytes.
    mutating func lengthPrefixedString(_ field: String) throws -> String {
        let length = Int(try u8(field))
        let raw = try bytes(length, field)
        guard let string = String(data: raw, encoding: .utf8) else {
            throw ProtocolDecodingError.invalidValue(field: field)
        }
        return string
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }
}

/// A wire code that is either one this client knows or a raw value from a
/// newer controller. Unknown codes are kept, so the UI can show `unknown (n)`.
public enum WireValue<Known>: Equatable, Sendable, CustomStringConvertible
where Known: RawRepresentable & Equatable & Sendable, Known.RawValue == UInt8 {
    case known(Known)
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        if let known = Known(rawValue: rawValue) {
            self = .known(known)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .known(let known): known.rawValue
        case .unknown(let raw): raw
        }
    }

    /// The known value, or nil for a code this client does not know.
    public var known: Known? {
        if case .known(let known) = self { return known }
        return nil
    }

    public var description: String {
        switch self {
        case .known(let known): String(describing: known)
        case .unknown(let raw): "unknown (\(raw))"
        }
    }
}
