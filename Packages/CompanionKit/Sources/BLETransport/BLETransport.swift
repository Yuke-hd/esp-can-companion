import Foundation

/// Connection state of the BLE link to a companion controller.
///
/// The CoreBluetooth manager arrives in a later change; this module only owns
/// moving bytes over BLE and never interprets protocol messages.
public enum LinkState: Equatable, Sendable {
    case idle
    case scanning
    case connecting
    case connected
    case disconnected(reason: String?)
}
