import Foundation

/// CRC-32/ISO-HDLC (the zlib and PNG CRC): polynomial `0x04C11DB7`, reflected
/// input and output, initial value and final XOR `0xFFFFFFFF`.
/// The check value over the ASCII bytes `123456789` is `0xCBF43926`.
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in
            crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
        }
    }

    public static func checksum<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        ~bytes.reduce(UInt32.max) { crc, byte in
            table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
    }
}
