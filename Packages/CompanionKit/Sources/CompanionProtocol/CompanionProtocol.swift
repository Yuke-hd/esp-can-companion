import Foundation

/// Namespace for the companion BLE protocol client and codecs.
///
/// This module stays free of CoreBluetooth and SwiftUI so it can be tested
/// against golden vectors on any host. The wire format follows the companion
/// spec in Yuke-hd/mazda-can-accessory-controller, `docs/specs/companion/`.
public enum CompanionProtocol {
    /// Protocol major version this client targets.
    public static let supportedVersion: UInt8 = 1
    /// Protocol major versions this client can talk to.
    public static let supportedProtocolMajors: Set<UInt8> = [supportedVersion]
    /// Highest protocol minor version this client knows. A newer minor is
    /// compatible: the client ignores fields, flag bits and codes it does not know.
    public static let knownProtocolMinor: UInt8 = 0
    /// Controller config schema versions `ControllerConfig` models.
    public static let supportedConfigSchemaVersions: Set<UInt16> = [1]
    /// Live signals frame layouts `LiveSignalFrame` decodes.
    public static let supportedLiveSignalLayouts: Set<UInt8> = [LiveSignalFrame.layoutVersion]
}
