import Foundation
import BLETransport
import CompanionProtocol

/// Answers companion protocol reads and writes for a `FakeRadio`, so the app,
/// previews and tests can run end to end without hardware. All values are
/// synthetic.
///
/// It serves Device info, Config status and paged Config reads, and with
/// `streamLiveSignals(on:from:)` a synthetic drive on Live signals. Config
/// uploads and commands are not simulated yet: those writes fail with
/// Unsupported Operation (`0x81`).
@MainActor
public final class DemoController {
    public var deviceInfo: DeviceInfo
    public var activeSource: ConfigSourceCode
    /// Canonical JSON of the active config. Empty when `activeSource` is `.none`.
    public var activeDocument: Data
    public var bootFlags: ConfigStatus.BootFlags
    /// The Config status `state`, such as `.restartPending` after a commit.
    public var state: ConfigStatus.StateCode = .idle

    private var readPageOffset = 0
    /// The demo drive started by `streamLiveSignals(on:from:)`.
    var liveSignalTask: Task<Void, Never>?

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
    }

    /// Makes `radio` answer reads and writes as this controller; the radio
    /// keeps it alive. `FakeRadio` takes one handler of each kind, so one demo
    /// controller serves every fake peripheral on it.
    public func attach(to radio: FakeRadio) {
        radio.readHandler = { _, characteristic in self.read(characteristic) }
        radio.writeHandler = { characteristic, value in self.write(value, to: characteristic) }
    }

    // MARK: Protocol

    func read(_ characteristic: GATTUUID) -> Result<Data, RadioError> {
        switch characteristic {
        case CompanionGATT.deviceInfo: .success(Self.encode(deviceInfo))
        case CompanionGATT.configStatus: .success(statusValue())
        case CompanionGATT.config: .success(readPage())
        default: .failure(.att(0x02)) // Read Not Permitted
        }
    }

    func write(_ value: Data, to characteristic: GATTUUID) -> RadioError? {
        let bytes = [UInt8](value)
        guard characteristic == CompanionGATT.config, let opcode = bytes.first else {
            return .att(ATTErrorCode.unsupportedOperation.rawValue)
        }
        switch opcode {
        case 0x04: // Abort: harmless when no transfer is open.
            return bytes.count == 1 ? nil : .att(ATTErrorCode.invalidAttributeValueLength.rawValue)
        case 0x05: // Select read page.
            guard bytes.count == 3 else { return .att(ATTErrorCode.invalidAttributeValueLength.rawValue) }
            let offset = Int(bytes[1]) | Int(bytes[2]) << 8
            guard offset <= activeDocument.count else { return .att(ATTErrorCode.invalidPDU.rawValue) }
            readPageOffset = offset
            return nil
        default:
            return .att(ATTErrorCode.unsupportedOperation.rawValue)
        }
    }

    private var activeCRC: UInt32 {
        activeDocument.isEmpty ? 0 : CRC32.checksum(activeDocument)
    }

    private func readPage() -> Data {
        let offset = min(readPageOffset, activeDocument.count)
        var page = Data([activeSource.rawValue])
        page.appendUInt16(UInt16(activeDocument.count))
        page.appendUInt32(activeCRC)
        page.appendUInt16(UInt16(offset))
        let start = activeDocument.startIndex + offset
        let end = min(activeDocument.endIndex, start + ConfigReadPage.maximumDataLength)
        page.append(activeDocument[start..<end])
        return page
    }

    /// Config status with no transfer data and no diagnostics.
    private func statusValue() -> Data {
        var value = Data([state.rawValue, 0, bootFlags.rawValue, activeSource.rawValue])
        value.appendUInt16(UInt16(activeDocument.count))
        value.appendUInt32(activeCRC)
        value.append(Data(count: ConfigStatus.minimumLength - value.count))
        return value
    }

    static func encode(_ info: DeviceInfo) -> Data {
        var value = Data([info.protocolMajor, info.protocolMinor])
        value.appendUInt16(info.configSchemaVersion)
        value.append(contentsOf: [info.liveSignalLayoutVersion, info.flags])
        value.appendUInt16(info.maxConfigBytes)
        for string in [info.firmwareVersion, info.hardwareID] {
            value.append(UInt8(string.utf8.count))
            value.append(contentsOf: string.utf8)
        }
        return value
    }

    // MARK: Sample data

    nonisolated public static let defaultDeviceInfo = DeviceInfo(
        protocolMajor: 1, protocolMinor: 0, configSchemaVersion: 1, liveSignalLayoutVersion: 1,
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

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }
}
