import Foundation
import BLETransport
import CompanionProtocol
import CompanionFakes

/// Runs the companion protocol on a fake radio for the Simulator and previews.
/// Values and controller validation verdicts are synthetic. Uploads and factory
/// reverts restart the peripheral so the real session re-reads the active config.
/// `streamLiveSignals(on:from:)` supplies synthetic Live signals.
@MainActor
public final class DemoController {
    private let controller = CompanionFakes.FakeController()
    private var restartScheduled = false
    /// The demo drive started by `streamLiveSignals(on:from:)`.
    var liveSignalTask: Task<Void, Never>?

    public var deviceInfo: DeviceInfo {
        get { controller.deviceInfo }
        set { controller.deviceInfo = newValue }
    }
    public var activeSource: ConfigSourceCode {
        get { ConfigSourceCode(rawValue: controller.activeSource) ?? .none }
        set { controller.activeSource = newValue.rawValue }
    }
    /// Canonical JSON of the active config. Empty when `activeSource` is `.none`.
    public var activeDocument: Data {
        get { controller.activeDocument }
        set { controller.activeDocument = newValue }
    }
    public var bootFlags: ConfigStatus.BootFlags {
        get { .init(rawValue: controller.bootFlags) }
        set { controller.bootFlags = newValue.rawValue }
    }
    public var state: ConfigStatus.StateCode {
        get { ConfigStatus.StateCode(rawValue: controller.state) ?? .idle }
        set { controller.state = newValue.rawValue }
    }
    /// Forces the controller's validation-error demo, without client validation.
    public var rejectsConfig: Bool {
        get {
            if case .reject = controller.commitOutcome { return true }
            return false
        }
        set {
            controller.commitOutcome = newValue
                ? .reject(category: 3, code: 10, validation: 18, index: 4, path: "outputs[4].zone.length")
                : .save
        }
    }

    public init(
        deviceInfo: DeviceInfo = DemoController.defaultDeviceInfo,
        activeSource: ConfigSourceCode = .factory,
        activeDocument: Data = DemoController.factoryDocument,
        bootFlags: ConfigStatus.BootFlags = []
    ) {
        self.deviceInfo = deviceInfo
        self.activeSource = activeSource
        self.activeDocument = activeSource == .none ? Data() : activeDocument
        self.bootFlags = bootFlags
        controller.factoryDocument = Self.factoryDocument
    }

    /// A demo controller serves all the peripherals on this radio.
    public func attach(to radio: FakeRadio, scheduler: BLEScheduler? = nil) {
        let scheduler = scheduler ?? MainActorScheduler()
        radio.readHandler = { _, characteristic in self.read(characteristic) }
        radio.writeHandler = { [weak radio] characteristic, value in
            guard let radio else { return .other("Demo radio unavailable") }
            let before = self.controller.statusValue()
            let error = self.write(value, to: characteristic)
            let after = self.controller.statusValue()
            if before != after {
                for id in radio.connectedPeripherals {
                    radio.sendNotification(from: id, characteristic: CompanionGATT.configStatus, data: after, immediately: true)
                }
            }
            let commits = characteristic == CompanionGATT.config && value == ConfigWritePDU.commit.encoded
            let reverts = characteristic == CompanionGATT.command && value == CompanionCommand.revertToFactory.encoded
            if error == nil, self.state == .restartPending, commits || reverts {
                self.scheduleRestart(on: radio, scheduler: scheduler)
            }
            return error
        }
    }

    func read(_ characteristic: GATTUUID) -> Result<Data, RadioError> {
        guard let role = ConnectionManagerTransport.characteristic(for: characteristic) else { return .failure(.att(0x02)) }
        do { return .success(try controller.readImmediately(role)) }
        catch { return .failure(Self.radioError(error)) }
    }

    func write(_ value: Data, to characteristic: GATTUUID) -> RadioError? {
        guard let role = ConnectionManagerTransport.characteristic(for: characteristic) else {
            return .att(ATTErrorCode.unsupportedOperation.rawValue)
        }
        do { try controller.writeImmediately(value, to: role); return nil }
        catch { return Self.radioError(error) }
    }

    private func scheduleRestart(on radio: FakeRadio, scheduler: BLEScheduler) {
        guard !restartScheduled else { return }
        restartScheduled = true
        let ids = radio.connectedPeripherals
        // The write response and Saved notification arrive before the restart.
        scheduler.schedule(after: 0.2) { [weak radio] in
            guard let radio else { return }
            ids.forEach { radio.powerOff($0) }
        }
        scheduler.schedule(after: 0.6) { [weak radio, self] in
            controller.restart()
            restartScheduled = false
            ids.forEach { radio?.powerOn($0) }
        }
    }

    private static func radioError(_ error: Error) -> RadioError {
        if case .att(let att) = error as? CompanionTransportError { return .att(att.rawValue) }
        return .other(String(describing: error))
    }

    static func encode(_ info: DeviceInfo) -> Data { CompanionFakes.FakeController.encode(info) }

    // MARK: Sample data

    nonisolated public static let defaultDeviceInfo = DeviceInfo(
        protocolMajor: 1, protocolMinor: 0, configSchemaVersion: 1, liveSignalLayoutVersion: 2,
        flags: 0, maxConfigBytes: 4096, firmwareVersion: "0.4.0-demo", hardwareID: "weact-can485-v1.1"
    )

    /// A verbatim copy of the firmware example
    /// `docs/specs/configuration/examples/controller-config-v1.json` (firmware 9ba94a0).
    nonisolated public static let factoryDocument = Data(#"{"actions":[{"name":"left_turn"},{"name":"right_turn"},{"name":"hazard"},{"name":"rpm_fill"},{"name":"red_zone"},{"name":"brake"}],"outputs":[{"action":"left_turn","effect":"right_turn","priority":100,"type":"led_effect"},{"action":"right_turn","effect":"left_turn","priority":100,"type":"led_effect"},{"action":"hazard","effect":"left_turn","priority":100,"type":"led_effect"},{"action":"hazard","effect":"right_turn","priority":100,"type":"led_effect"},{"action":"rpm_fill","color":{"blue":32,"green":16,"red":0},"priority":50,"type":"led_fill","zone":{"direction":"center_out","length":100,"start":0}},{"action":"red_zone","color":{"blue":0,"green":0,"red":16},"priority":150,"type":"led_solid","zone":{"direction":"start_to_end","length":30,"start":35}},{"action":"brake","color":{"blue":0,"green":0,"red":16},"priority":200,"type":"led_solid","zone":{"direction":"start_to_end","length":30,"start":35}}],"rules":[{"action":"left_turn","comparison":"equal","freshness":"fresh","operand":{"choice":"left"},"signal_key":"vehicle.turn_state","type":"state"},{"action":"right_turn","comparison":"equal","freshness":"fresh","operand":{"choice":"right"},"signal_key":"vehicle.turn_state","type":"state"},{"action":"hazard","comparison":"equal","freshness":"fresh","operand":{"choice":"hazard"},"signal_key":"vehicle.turn_state","type":"state"},{"action":"rpm_fill","freshness":"fresh_or_unverified","input":{"from":0,"to":6500},"output":{"from":0,"to":1},"signal_key":"vehicle.engine_rpm","type":"range"},{"action":"red_zone","comparison":"greater","freshness":"fresh_or_unverified","operand":{"number":6000},"signal_key":"vehicle.engine_rpm","type":"sampled_state"},{"action":"brake","comparison":"equal","freshness":"fresh_or_unverified","operand":{"boolean":true},"signal_key":"vehicle.brake_pressed","type":"state"}],"version":1}"#.utf8)

    /// A small custom override: a brake light and a shift light.
    nonisolated public static let customDocument: Data = {
        let config = ControllerConfig(
            actions: [.init(name: "brake"), .init(name: "shift_light")],
            rules: [
                .state(.init(action: "brake", signalKey: "vehicle.brake_pressed", comparison: .equal, operand: .boolean(true))),
                .sampledState(
                    .init(action: "shift_light", signalKey: "vehicle.engine_rpm", comparison: .greaterOrEqual, operand: .number(5800)),
                    releaseThreshold: 5500
                ),
            ],
            outputs: [
                .ledSolid(.init(
                    action: "brake",
                    zone: .init(start: 0, length: 20, direction: .startToEnd),
                    color: .init(red: 24, green: 0, blue: 0),
                    priority: 200
                )),
                .ledTransient(.init(
                    action: "shift_light",
                    zone: .init(start: 20, length: 10, direction: .centerOut),
                    color: .init(red: 0, green: 24, blue: 8)
                ), durationMs: 400),
            ]
        )
        return (try? config.encodedJSON()) ?? Data()
    }()
}
