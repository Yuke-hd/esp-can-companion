import Foundation

/// Namespace for the companion BLE protocol client and codecs.
///
/// Message types and codecs arrive in a later change. This module stays free of
/// CoreBluetooth and SwiftUI so it can be tested against golden vectors on any host.
public enum CompanionProtocol {
    /// Protocol version this client targets.
    public static let supportedVersion: UInt8 = 1
}
