import Foundation
import BLETransport
import CompanionProtocol

/// Ready-made controller sessions on the fake radio, for SwiftUI previews and
/// the Simulator. Pass `-DemoScenario <name>` at launch to pick one.
public enum DemoScenario: String, CaseIterable, Sendable {
    /// Bluetooth on, no controller paired yet. Connect scans and finds one.
    case notPaired
    /// The remembered controller is out of range, so the request is pending.
    case connecting
    /// Linked to a controller running its factory config.
    case connected
    /// Linked to a controller running a custom override.
    case customConfig
    /// The link was up, then the controller lost power; the app waits for it.
    case relinking
    /// The controller speaks protocol version 2, which this app does not.
    case incompatible
    case bluetoothOff
    /// The user denied Bluetooth access.
    case noAccess

    /// A session for this scenario. Pass `latency` 0 for snapshots or tests
    /// that should settle at once on the main actor's next turns.
    @MainActor
    public func makeSession(latency: TimeInterval = 0.4) -> ControllerSession {
        let scheduler = MainActorScheduler()
        var peripheral = FakeController(name: "Demo Controller")
        var remembered: PeripheralID? = peripheral.id
        var radioState = RadioState.poweredOn
        let demo = DemoController()

        switch self {
        case .notPaired:
            remembered = nil
        case .connecting:
            peripheral.isPoweredOn = false
        case .connected, .relinking:
            break
        case .customConfig:
            demo.activeSource = .persistedOverride
            demo.activeDocument = DemoController.customDocument
        case .incompatible:
            peripheral.protocolMajor = 2
            demo.deviceInfo.protocolMajor = 2
        case .bluetoothOff:
            radioState = .poweredOff
        case .noAccess:
            radioState = .unauthorized
        }

        let radio = FakeRadio(controllers: [peripheral], state: radioState, scheduler: scheduler, latency: latency)
        demo.attach(to: radio)
        demo.streamLiveSignals(on: radio, from: peripheral.id)
        let manager = ConnectionManager(
            radio: radio,
            store: InMemoryDeviceStore(rememberedDeviceID: remembered),
            scheduler: scheduler
        )
        let session = ControllerSession(connection: manager)
        if self == .relinking {
            let id = peripheral.id
            var token: ObservationToken?
            token = manager.observeState { state in
                guard state.isConnected else { return }
                token?.cancel()
                radio.powerOff(id)
            }
        }
        manager.start()
        return session
    }
}
