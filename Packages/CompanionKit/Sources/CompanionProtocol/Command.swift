import Foundation

/// A write to the Command characteristic. Both commands end the connection.
public enum CompanionCommand: UInt8, Equatable, Sendable, CaseIterable {
    /// Clears the persisted config override, then restarts.
    case revertToFactory = 0x01
    /// Deletes every stored bond, then disconnects.
    case clearBonds = 0x02

    /// The opcode followed by its check byte (`opcode XOR 0xFF`).
    public var encoded: Data {
        Data([rawValue, rawValue ^ 0xFF])
    }
}
