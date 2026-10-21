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
    /// Catalog-driven fixtures for the read-only discovered-signal sheet.
    case discoveredSignals, discoveredPartial, discoveredStalled, discoveredMalformed
    case discoveredReconnect, discoveredUnsupported, discoveredUnusable, discoveredCatalogFailure

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
        case .connected, .relinking, .stalled, .selectorCycle, .driveLaps,
             .discoveredSignals, .discoveredPartial, .discoveredStalled, .discoveredMalformed,
             .discoveredReconnect, .discoveredCatalogFailure:
            break
        case .discoveredUnsupported:
            demo.deviceInfo.protocolMinor = 0
            demo.deviceInfo.extensionVersion = nil
            demo.deviceInfo.extensionFlags = nil
        case .discoveredUnusable:
            demo.deviceInfo.extensionFlags = 0
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

        if isDiscoveredJourney { demo.signalCatalog = Self.journeyCatalog(remapped: false) }
        let radio = FakeRadio(controllers: [peripheral], state: radioState, scheduler: scheduler, latency: latency)
        demo.attach(to: radio, scheduler: scheduler)
        if self == .discoveredCatalogFailure {
            radio.readHandler = { _, characteristic in
                characteristic == CompanionGATT.signalCatalog ? .failure(.att(0x83)) : demo.read(characteristic)
            }
        }
        let frames: @Sendable (Double, UInt8) -> DemoTelemetry = switch self {
        case .selectorCycle: { DemoTelemetry.selectorCycle(at: $0, sequence: $1) }
        case .driveLaps, .driveLapsLayout1: { DemoTelemetry.driveLaps(at: $0, sequence: $1) }
        default: { DemoTelemetry.drive(at: $0, sequence: $1) }
        }
        if isDiscoveredJourney {
            startJourney(demo: demo, radio: radio, peripheral: peripheral.id)
        } else {
            demo.streamLiveSignals(
                on: radio, from: peripheral.id,
                stopAfter: self == .stalled ? .seconds(3) : nil, frames: frames
            )
        }
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
        if self == .discoveredReconnect {
            var observation: ObservationToken?
            observation = manager.observeNotifications { characteristic, data in
                guard characteristic == CompanionGATT.extensibleLiveSignals,
                      let packet = try? ExtensibleLiveSignalPacket(decoding: data),
                      !packet.records.isEmpty else { return }
                observation?.cancel()
                // Begin the event window only after actual valid data traversed
                // the notifier. Startup/catalog latency cannot consume it.
                scheduler.schedule(after: 6) {
                    demo.signalCatalog = Self.journeyCatalog(remapped: true)
                    self.startJourney(demo: demo, radio: radio, peripheral: peripheral.id, remapped: true)
                    radio.powerCycle(peripheral.id, offFor: 2)
                }
            }
        }
        manager.start()
        return session
    }

    private var isDiscoveredJourney: Bool { rawValue.hasPrefix("discovered") }

    private static func journeyCatalog(remapped: Bool) -> DemoSignalCatalog {
        // Synthetic connection-local handles and evidence; no vehicle claims.
        let handles: [UInt16] = remapped ? [400, 300, 200, 100] : [100, 200, 300, 400]
        return try! DemoSignalCatalog(token: 0x12345678, entries: [
            .init(handle: handles[0], key: "example.enabled", type: .boolean),
            .init(handle: handles[1], key: "example.mode", type: .enumeration,
                  choices: remapped ? ["new_choice", "idle"] : ["idle", "new_choice"]),
            .init(handle: handles[2], key: "example.peer", type: .number, unit: "none"),
            .init(handle: handles[3], key: "example.signed", type: .number, unit: "m/s^2"),
        ])
    }

    @MainActor
    private func startJourney(demo: DemoController, radio: FakeRadio, peripheral: PeripheralID,
                              remapped: Bool = false) {
        demo.streamLiveSignals(
            on: radio, from: peripheral,
            stopAfter: self == .discoveredStalled ? .seconds(8) : nil,
            extensibleFrames: { seconds, _ in [
                "example.enabled": .init(availability: .fresh,
                                         value: .boolean(!remapped && !(self == .discoveredMalformed && seconds >= 45))),
                "example.mode": .init(availability: .freshnessUnverified, value: .enumeration(choiceKey: "new_choice")),
                "example.peer": .init(availability: .fresh, value: .number(Float(seconds))),
                "example.signed": .init(availability: self == .discoveredPartial ? .stale : .fresh,
                                        value: .number(remapped ? 2.5 : -1.25)),
            ] },
            extensibleSelection: { seconds in
                self == .discoveredPartial && seconds >= 6 ? [200, 300, 400] : nil
            },
            transformExtensiblePackets: { seconds, packets in
                self == .discoveredMalformed && seconds >= 45 ? packets.map { $0 + Data([1]) } : packets
            }
        )
    }

}
