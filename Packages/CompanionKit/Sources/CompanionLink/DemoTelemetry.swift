import Foundation
import BLETransport
import CompanionProtocol

/// Synthetic Live signals frames for the demo controller: a car pulling
/// through the gears with the left indicator on, so the Pit Wall moves in
/// previews and the Simulator. All values are made up.
///
/// Frames use layout 2 (28 bytes, with acceleration) unless `layoutVersion`
/// says 1, so the same drives can exercise a layout 1 controller.
public struct DemoTelemetry: Equatable, Sendable {
    /// Status nibble values (live-signals.md, "Status nibbles").
    public enum Status: UInt8, Sendable {
        case fresh = 0x9 // Fresh, value present
        case unverified = 0xB // FreshnessUnverified, value present
        case stale = 0x2 // Stale, no value
        case noData = 0x0
    }

    /// Live signals layout to encode: 2 (default) or 1, which has no acceleration.
    public var layoutVersion: UInt8 = LiveSignalFrame.layout2Version
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
    /// Layout 2 only. In m/s²; positive is accelerating. The axis and sign are
    /// unvalidated reference candidates, as in the protocol.
    public var longitudinalAcceleration: Double = 0
    /// Layout 2 only. In m/s²; positive is a right turn, an
    /// unvalidated reference candidate like the longitudinal sign.
    public var lateralAcceleration: Double = 0
    /// One status per signal index, 0...20. Layout 1 sends only 0...18.
    public var statuses: [Status] = Array(repeating: .unverified, count: 21)

    /// As on the car: only turn state, hazard, the turn requests and (in
    /// layout 2) acceleration have a freshness timeout, so only they can be
    /// fresh. Everything else, brake included, arrives unverified.
    public static let freshIndices = [2, 6, 7, 8, 19, 20]

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
        // Easing off as each gear winds out.
        frame.longitudinalAcceleration = 3.5 - pull * 2
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
        // Each change passes through a short shifting window, as the car
        // reports between positions, so Drive must animate across it.
        let isShifting = seconds.truncatingRemainder(dividingBy: 2.5) < 0.4
        frame.selectorPosition = isShifting ? .shifting : step.0
        frame.actualGear = isShifting ? .shifting : step.1
        frame.engineRPM = 800
        frame.speedKPH = 0
        return frame
    }

    /// How long one lap of `driveLaps` takes before it repeats, in seconds.
    public static let driveLapDuration: Double = 24

    /// A synthetic lap at `seconds` since it started, for the g-meter:
    /// launch, braking, a left and a right corner, a stop, and windows where
    /// one or both acceleration axes are not fresh. It loops every
    /// `driveLapDuration` seconds.
    public static func driveLaps(at seconds: Double, sequence: UInt8) -> DemoTelemetry {
        var frame = DemoTelemetry()
        frame.sequence = sequence
        let t = seconds.truncatingRemainder(dividingBy: driveLapDuration)
        /// Progress 0...1 through the phase from `start` to `end`.
        func progress(_ start: Double, _ end: Double) -> Double { (t - start) / (end - start) }
        func lerp(_ from: Double, _ to: Double, _ p: Double) -> Double { from + (to - from) * p }
        let brake: UInt16 = 1 << 12

        switch t {
        case ..<4: // Launch from standstill through first and second.
            let p = progress(0, 4)
            frame.longitudinalAcceleration = lerp(4.5, 2.5, p)
            frame.lateralAcceleration = 0.2 * sin(t * 3)
            frame.speedKPH = lerp(0, 60, p)
            frame.actualGear = p < 0.5 ? .first : .second
            frame.engineRPM = 2500 + (p.truncatingRemainder(dividingBy: 0.5) / 0.5) * 4000
        case ..<6.5: // Hard braking for the first corner.
            let p = progress(4, 6.5)
            frame.longitudinalAcceleration = lerp(-7.5, -5, p)
            frame.speedKPH = lerp(60, 35, p)
            frame.actualGear = .second
            frame.engineRPM = lerp(4200, 2800, p)
            frame.booleans = brake
        case ..<10.5: // A long left-hander, trail braking onto the throttle.
            let p = progress(6.5, 10.5)
            frame.lateralAcceleration = -6.5 * sin(.pi * p)
            frame.longitudinalAcceleration = lerp(-0.5, 1.5, p)
            frame.speedKPH = lerp(35, 50, p)
            frame.actualGear = .second
            frame.engineRPM = lerp(2800, 4000, p)
        case ..<11.5: // The acceleration source drops out: both axes stale.
            frame.longitudinalAcceleration = 1.5
            frame.statuses[19] = .stale
            frame.statuses[20] = .stale
            frame.speedKPH = 52
            frame.actualGear = .third
            frame.engineRPM = 3000
        case ..<15.5: // A right-hander.
            let p = progress(11.5, 15.5)
            frame.lateralAcceleration = 6 * sin(.pi * p)
            frame.longitudinalAcceleration = 1
            frame.speedKPH = lerp(52, 60, p)
            frame.actualGear = .third
            frame.engineRPM = lerp(3000, 3500, p)
        case ..<17.5: // Lateral present but unverified; only longitudinal is live.
            let p = progress(15.5, 17.5)
            frame.longitudinalAcceleration = 2
            frame.lateralAcceleration = -0.8
            frame.statuses[20] = .unverified
            frame.speedKPH = lerp(60, 75, p)
            frame.actualGear = .third
            frame.engineRPM = lerp(3500, 4500, p)
        case ..<19.5: // Longitudinal has no data; only lateral is live.
            frame.lateralAcceleration = 0.5
            frame.statuses[19] = .noData
            frame.speedKPH = 75
            frame.actualGear = .fourth
            frame.engineRPM = 3200
        default: // Braking to a stop at the line, then waiting.
            let p = min(1, progress(19.5, 23))
            frame.longitudinalAcceleration = p < 1 ? -3 : 0
            frame.speedKPH = lerp(75, 0, p)
            frame.actualGear = p < 1 ? .third : .first
            frame.engineRPM = lerp(2600, 800, p)
            frame.booleans = brake
        }
        return frame
    }

    /// The encoded frame: 28 bytes for layout 2, otherwise the 23-byte layout 1.
    public var encoded: Data {
        let isLayout2 = layoutVersion == LiveSignalFrame.layout2Version
        var value = Data([layoutVersion, sequence, isTelemetryStarted ? 1 : 0])
        Self.append(UInt16((engineRPM * 4).rounded()), to: &value)
        Self.append(UInt16((speedKPH * 100).rounded()), to: &value)
        value.append(contentsOf: [turnState.rawValue, selectorPosition.rawValue, actualGear.rawValue, frontWiperPosition.rawValue])
        Self.append(booleans, to: &value)
        // 19 signals in layout 1, 21 in layout 2; unused nibbles are zero.
        let signals = isLayout2 ? 21 : 19
        func nibble(_ index: Int) -> UInt8 { index < signals ? statuses[index].rawValue : 0 }
        for pair in stride(from: 0, to: signals, by: 2) {
            value.append(nibble(pair) | nibble(pair + 1) << 4)
        }
        if isLayout2 {
            Self.append(UInt16(bitPattern: Int16(clamping: Int((longitudinalAcceleration * 100).rounded()))), to: &value)
            Self.append(UInt16(bitPattern: Int16(clamping: Int((lateralAcceleration * 1000).rounded()))), to: &value)
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
    /// connected. Like the firmware, frames use the layout Device info reports. Stops when the radio goes away or `stopAfter` elapses,
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
                var frame = frames(seconds, sequence)
                frame.layoutVersion = deviceInfo.liveSignalLayoutVersion
                radio.sendNotification(from: peripheral, characteristic: CompanionGATT.liveSignals, data: frame.encoded, immediately: true)
                sequence &+= 1
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
