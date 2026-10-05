import Foundation
import DesignSystem
import BLETransport
import CompanionProtocol
import CompanionLink

// Words the link and controller cards show for each state, kept apart from the views so
// unit tests can cover every case.

extension LinkState {
    var title: String {
        switch self {
        case .unknown: "Starting"
        case .unsupported: "No Bluetooth"
        case .unauthorized: "No access"
        case .poweredOff: "Bluetooth off"
        case .idle: "Not linked"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .pairing: "Pairing"
        case .connected: "Linked"
        case .disconnected(.unsupportedProtocol, _): "Incompatible"
        case .disconnected(_, let willReconnect): willReconnect ? "Relinking" : "Lost link"
        }
    }

    var detail: String {
        switch self {
        case .unknown: "Checking Bluetooth."
        case .unsupported: "This device does not support Bluetooth LE."
        case .unauthorized: "Allow Bluetooth access in Settings to talk to the controller."
        case .poweredOff: "Turn on Bluetooth in Control Center or Settings to connect."
        case .idle: "No controller paired yet."
        case .scanning: "Looking for controllers nearby."
        case .connecting: "Waiting for the controller. It connects as soon as it is in range."
        case .pairing: "Pairing with the controller."
        case .connected(let device): "Connected to \(device.name ?? "the controller")."
        case .disconnected(let reason, _):
            switch reason {
            case .userRequested: "Disconnected."
            case .connectionLost: "Lost the connection. Waiting for the controller to come back."
            case .connectFailed: "Could not connect. Retrying."
            case .pairingFailed: "Pairing did not complete. Press the user key on the controller to allow pairing for 120 seconds, then try again."
            case .bondRemoved: "The controller forgot this phone. Forget it in iOS Settings > Bluetooth, then pair again."
            case .incompatibleDevice: "This device is not a companion controller."
            case .unsupportedProtocol(let major): "This controller speaks protocol version \(major). Update the app or the controller firmware."
            }
        }
    }

    var pillStatus: StatusPill.Status {
        switch self {
        case .idle, .unknown: .neutral
        case .scanning, .connecting, .pairing: .pending
        case .connected: .live
        case .disconnected(_, let willReconnect): willReconnect ? .pending : .alert
        case .unsupported, .unauthorized, .poweredOff: .alert
        }
    }
}

extension ConfigSource {
    /// Which config the controller is running, as the controller card names it.
    var title: String {
        switch self {
        case .known(.factory): "Factory default"
        case .known(.persistedOverride): "Custom override"
        case .known(.none): "None"
        case .unknown(let raw): "Unknown (\(raw))"
        }
    }
}

extension ConfigStatus {
    /// Problems the controller reported at boot, worst first.
    var bootWarnings: [String] {
        var warnings: [String] = []
        if bootFlags.contains(.lightingSetupFailed) {
            warnings.append("Lighting setup failed, so the LEDs are off.")
        }
        if bootFlags.contains(.overrideInvalid) {
            warnings.append("The saved custom config was invalid, so the controller is running its factory default.")
        }
        if bootFlags.contains(.overrideReadFailed) {
            warnings.append("The saved custom config could not be read, so the controller is running its factory default.")
        }
        if bootFlags.contains(.noConfigStore) {
            warnings.append("The controller has no config storage this boot, so uploads will fail.")
        }
        return warnings
    }
}

extension DeviceInfo {
    var protocolText: String { "v\(protocolMajor).\(protocolMinor)" }
}

extension ControllerSession.Phase {
    /// What the controller card says when there are no details to show.
    func message(for link: LinkState) -> String? {
        switch self {
        case .offline:
            if case .disconnected(.unsupportedProtocol(let major), _) = link {
                return "Protocol version \(major) is not supported by this app."
            }
            return "Connect to see the firmware and active config."
        case .loading:
            return "Reading the controller."
        case .incompatible(let major):
            return "This controller speaks protocol version \(major). Update the app or the controller firmware."
        case .failed(let message):
            return message
        case .ready:
            return nil
        }
    }
}

extension ConfigSummary.Action {
    /// One VoiceOver label for the whole row.
    var accessibilityText: String {
        var parts = [title]
        parts += triggers
        if outputs.isEmpty {
            parts.append("No outputs")
        } else {
            parts += outputs.map { "Output: \($0)" }
        }
        return parts.joined(separator: ". ")
    }
}
