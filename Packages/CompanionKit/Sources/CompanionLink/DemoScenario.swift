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
    /// Linked to a controller whose live stream stops after valid frames.
    case stalled
    /// Linked to a parked car whose selector steps through P, R, N and D.
    case selectorCycle
    /// Linked to a layout 2 controller driving laps for the g-meter: launch,
    /// braking, left and right corners, with acceleration dropouts.
    case driveLaps
    /// The same laps from a controller that reports layout 1, so frames carry
    /// no acceleration.
    case driveLapsLayout1
    /// Uploads receive a synthetic controller validation rejection.
    case validationError
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
        case .connected, .relinking, .stalled, .selectorCycle, .driveLaps:
            break
        case .driveLapsLayout1:
            demo.deviceInfo.liveSignalLayoutVersion = LiveSignalFrame.layoutVersion
        case .validationError:
            demo.rejectsConfig = true
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
        demo.attach(to: radio, scheduler: scheduler)
        let frames: @Sendable (Double, UInt8) -> DemoTelemetry = switch self {
        case .selectorCycle: DemoTelemetry.selectorCycle
        case .driveLaps, .driveLapsLayout1: DemoTelemetry.driveLaps
        default: DemoTelemetry.drive
        }
        demo.streamLiveSignals(
            on: radio,
            from: peripheral.id,
            stopAfter: self == .stalled ? .seconds(3) : nil,
            frames: frames
        )
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
