import Foundation
import BLETransport
import CompanionProtocol

/// Synthetic Live signals frames for the demo controller: a car pulling
/// through the gears with the left indicator on, so the Pit Wall moves in
/// previews and the Simulator. All values are made up.
public struct DemoTelemetry: Equatable, Sendable {
    /// Status nibble values (live-signals.md, "Status nibbles").
    public enum Status: UInt8, Sendable {
        case fresh = 0x9 // Fresh, value present
        case unverified = 0xB // FreshnessUnverified, value present
        case stale = 0x2 // Stale, no value
        case noData = 0x0
    }

    public var sequence: UInt8 = 0
    public var isTelemetryStarted = true
    public var engineRPM: Double = 0
    public var speedKPH: Double = 0
    public var turnState: TurnState = .off
    public var selectorPosition: SelectorPosition = .drive
    public var actualGear: ActualGear = .first
    public var frontWiperPosition: FrontWiperPosition = .off
    /// Bit per Boolean signal, in the spec's bit order.
    public var booleans: UInt16 = 0
    /// One status per signal index, 0...18.
    public var statuses: [Status] = Array(repeating: .unverified, count: 19)

    /// As on the car: only turn state, hazard and the turn requests have a
    /// freshness timeout, so only they can be fresh. Everything else,
    /// brake included, arrives unverified.
    public static let freshIndices = [2, 6, 7, 8]

    public init() {
        for index in Self.freshIndices { statuses[index] = .fresh }
        // A wiper sensor that went quiet.
        statuses[5] = .stale
        statuses[17] = .stale
    }

    /// The demo drive at `seconds` since it started; it loops every 12 s.
    public static func drive(at seconds: Double, sequence: UInt8) -> DemoTelemetry {
        var frame = DemoTelemetry()
        frame.sequence = sequence
        let t = seconds.truncatingRemainder(dividingBy: 12)
        // Four pulls from 2,500 to 6,400 rpm, one per gear.
        let pull = t.truncatingRemainder(dividingBy: 3) / 3
        let gear = Int(t / 3)
        frame.engineRPM = 2500 + pull * 3900
        frame.actualGear = [.second, .third, .fourth, .fifth][gear]
        frame.speedKPH = 30 + Double(gear) * 22 + pull * 20
        let indicatorOn = Int(seconds * 2.5).isMultiple(of: 2)
        frame.turnState = .left
        frame.booleans = (1 << 1) // turn request left
            | (indicatorOn ? 1 << 3 : 0) // left indicator lamp
        return frame
    }

    /// A parked car moved through the selector at `seconds` since it started:
    /// P, R, N, D, N, R, one step every 2.5 s, looping.
    public static func selectorCycle(at seconds: Double, sequence: UInt8) -> DemoTelemetry {
        var frame = DemoTelemetry()
        frame.sequence = sequence
        let steps: [(SelectorPosition, ActualGear)] = [
            (.park, .park), (.reverse, .reverse), (.neutral, .neutral),
            (.drive, .first), (.neutral, .neutral), (.reverse, .reverse),
        ]
        let step = steps[Int(seconds / 2.5) % steps.count]
        frame.selectorPosition = step.0
        frame.actualGear = step.1
        frame.engineRPM = 800
        frame.speedKPH = 0
        return frame
    }

    /// The 23-byte layout version 1 frame.
    public var encoded: Data {
        var value = Data([LiveSignalFrame.layoutVersion, sequence, isTelemetryStarted ? 1 : 0])
        Self.append(UInt16((engineRPM * 4).rounded()), to: &value)
        Self.append(UInt16((speedKPH * 100).rounded()), to: &value)
        value.append(contentsOf: [turnState.rawValue, selectorPosition.rawValue, actualGear.rawValue, frontWiperPosition.rawValue])
        Self.append(booleans, to: &value)
        for pair in stride(from: 0, to: 20, by: 2) {
            let low = statuses[pair].rawValue
            let high = pair + 1 < statuses.count ? statuses[pair + 1].rawValue : 0
            value.append(low | high << 4)
        }
        return value
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }
}

extension DemoController {
    /// Sends `frames` (the demo drive by default) to `peripheral` on `radio` at 10 Hz while it is
    /// connected. Stops when the radio goes away or `stopAfter` elapses,
    /// leaving the link connected so the normal live-signal stall timeout can
    /// clear the last frame.
    public func streamLiveSignals(
        on radio: FakeRadio,
        from peripheral: PeripheralID,
        stopAfter: Duration? = nil,
        frames: @escaping @Sendable (Double, UInt8) -> DemoTelemetry = DemoTelemetry.drive
    ) {
        liveSignalTask?.cancel()
        liveSignalTask = Task { @MainActor [weak radio] in
            let start = ContinuousClock.now
            var sequence: UInt8 = 0
            while !Task.isCancelled {
                // Hold the radio only while sending, so it can go away while this sleeps.
                guard let radio else { return }
                let elapsed = ContinuousClock.now - start
                if let stopAfter, elapsed >= stopAfter { return }
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let frame = frames(seconds, sequence)
                radio.sendNotification(from: peripheral, characteristic: CompanionGATT.liveSignals, data: frame.encoded, immediately: true)
                sequence &+= 1
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
