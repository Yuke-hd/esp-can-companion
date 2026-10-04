import Foundation

/// ATT error codes the controller returns for failed writes, including the
/// protocol's application error range (`0x80`–`0x9F`).
public enum ATTErrorCode: UInt8, Equatable, Sendable {
    case insufficientAuthentication = 0x05
    case invalidAttributeValueLength = 0x0D
    case insufficientEncryption = 0x0F
    case invalidPDU = 0x80
    case unsupportedOperation = 0x81
    case busy = 0x82
    case invalidState = 0x83
    case storageFailure = 0x84
    case mtuTooSmall = 0x85
    case tooLarge = 0x86
    case offsetMismatch = 0x87
    case incomplete = 0x88
    case checksumMismatch = 0x89
    case configRejected = 0x8A
    case applyRejected = 0x8B
}

/// An ATT error code; unknown codes are treated as a generic failure of the operation.
public typealias ATTError = WireValue<ATTErrorCode>
