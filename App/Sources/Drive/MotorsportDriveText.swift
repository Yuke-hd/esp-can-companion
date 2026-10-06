import Foundation
import CompanionProtocol
import CompanionLink

/// Typed lamp and selector states for the Motorsport style. They are read
/// from the frame's typed values, never from Pit Wall's display words, and
/// each is gated by the matching readout freshness so a stale or unknown
/// signal can never light.
struct MotorsportSignals: Equatable {
    var leftLit = false
    var rightLit = false
    /// Nil while the brake value must not be shown.
    var brakePressed: Bool?
    /// Nil while the gear group is not current. `.shifting` and unknown
    /// codes (including unrecognised ones, as `.unknown`) are kept so the gear view can tell them apart from staleness.
    var selector: SelectorPosition?
    /// The gearbox or selector reports a change in progress.
    var isShifting = false

    static let off = MotorsportSignals()

    init() {}

    init(frame: LiveSignalFrame, readout: DriveReadout) {
        let turn = readout.turn.freshness.showsValue ? frame.turnState.value : nil
        let hazard = readout.hazard.freshness.showsValue && frame.hazardRequest.value == true
        leftLit = hazard || turn == .known(.left) || turn == .known(.hazard)
        rightLit = hazard || turn == .known(.right) || turn == .known(.hazard)
        brakePressed = readout.brake.freshness.showsValue ? frame.brakePressed.value : nil
        let gearShifting = readout.gearFreshness.showsValue && frame.actualGear.value == .known(.shifting)
        isShifting = gearShifting

        guard readout.gearFreshness.showsValue, readout.selectorFreshness.showsValue,
              let position = frame.selectorPosition.value else { return }
        switch position {
        case .known(let known):
            selector = known
            isShifting = isShifting || known == .shifting
        case .unknown: selector = .unknown
        }
    }
}

// Display and accessibility words for the Motorsport Drive style. Keeping
// these decisions beside the screen lets tests cover signal state without
// rendering SwiftUI.
extension DriveReadout {
    var rpmDisplayText: String { rpm.map { Int($0.rounded()).formatted() } ?? "—" }
    var speedDisplayText: String { speedKPH.map(String.init) ?? "—" }
    var gearDisplayText: String { gear ?? "—" }
    // The selector belongs to the same central gear group. When the gear
    // signal is stale, clear both values so the screen cannot imply a
    // current drivetrain state from a retained selector.
    var selectorDisplayText: String {
        gearFreshness.showsValue ? (selector ?? "—") : "—"
    }

    // Mid-shift the label reads "GEAR ?" instead of the word "Shift", and
    // the view hides the big numeral (owner direction). The dash keeps the
    // numeral's layout height while hidden.
    func gearDisplayText(shifting: Bool) -> String { shifting ? "—" : gearDisplayText }
    func selectorDisplayText(shifting: Bool) -> String { shifting ? "?" : selectorDisplayText }

    var gearAccessibilityText: String {
        let gear = self.gear.map { "Gear " + $0 } ?? "Gear, no value"
        let selector = gearFreshness.showsValue
            ? (self.selector.map { selectorName($0) } ?? "selector, no value")
            : "selector, no value"
        return [gear, selector, gearFreshness.title].joined(separator: ", ")
    }

    var rpmAccessibilityText: String {
        ["Engine RPM", rpmDisplayText, rpmFreshness.title].joined(separator: ", ")
    }

    var speedAccessibilityText: String {
        ["Speed", speedDisplayText + " kilometers per hour", speedFreshness.title].joined(separator: ", ")
    }

    var brakeAccessibilityText: String { tileAccessibility(brake) }
    var turnAccessibilityText: String { tileAccessibility(turn) }
    // Throttle has no live signal. Its wording follows the readout's
    // placeholder tile, so a future signal changes it in one place.
    var throttleDisplayText: String {
        throttle.freshness == .unsupported ? "NO SIGNAL" : throttle.freshness.title.uppercased()
    }
    var throttleAccessibilityText: String { ["Throttle", throttle.freshness.title].joined(separator: ", ") }

    // MARK: G-meter

    /// Why the g-meter shows no dot, or nil while both axes are live. When
    /// only one axis is missing it is named with its state, since the dot
    /// cannot be placed from the other alone.
    var gMeterStatusText: String? {
        guard acceleration == nil else { return nil }
        guard let (axis, freshness) = gMeterMissingAxis else { return "NO DATA" }
        return "\(axis.short) \(freshness.title.uppercased())"
    }

    /// Total g under the dial, one decimal, from the smoothed value the
    /// meter shows. A dash, never zero, while there is no live data.
    func gMeterValueText(_ smoothed: GForce?) -> String {
        guard acceleration != nil, let smoothed else { return "—" }
        return Self.gText(smoothed.magnitude)
    }

    /// One combined label, for example "G-meter, 0.4 g braking, 0.7 g right".
    /// Directions name the car's acceleration (positive lateral is a right
    /// turn), not where the dot sits. A component that rounds to zero is
    /// left out; when both do, the total is spoken as shown under the dial
    /// (for example "0.1 g"), so the label never contradicts the number.
    func gMeterAccessibilityText(_ smoothed: GForce?) -> String {
        guard acceleration != nil, let smoothed else {
            guard let (axis, freshness) = gMeterMissingAxis else { return "G-meter, no data" }
            return "G-meter, no data, \(axis.name) \(freshness.title.lowercased())"
        }
        let parts = [
            Self.gComponent(smoothed.longitudinal, positive: "accelerating", negative: "braking"),
            Self.gComponent(smoothed.lateral, positive: "right", negative: "left"),
        ].compactMap { $0 }
        return (["G-meter"] + (parts.isEmpty ? [Self.gText(smoothed.magnitude) + " g"] : parts)).joined(separator: ", ")
    }

    private enum GMeterAxis {
        case longitudinal, lateral

        var short: String { self == .longitudinal ? "LONG" : "LAT" }
        var name: String { self == .longitudinal ? "longitudinal" : "lateral" }
    }

    /// The one non-live axis while the other is live; nil when both are
    /// missing (or neither, which cannot plot either).
    private var gMeterMissingAxis: (GMeterAxis, PitWallReadout.Freshness)? {
        let longitudinalLive = longitudinalAccelerationFreshness == .fresh
        let lateralLive = lateralAccelerationFreshness == .fresh
        switch (longitudinalLive, lateralLive) {
        case (false, true): return (.longitudinal, longitudinalAccelerationFreshness)
        case (true, false): return (.lateral, lateralAccelerationFreshness)
        default: return nil
        }
    }

    private static func gText(_ value: Double) -> String {
        String(format: "%.1f", abs(value))
    }

    private static func gComponent(_ value: Double, positive: String, negative: String) -> String? {
        let text = gText(value)
        guard text != "0.0" else { return nil }
        return "\(text) g \(value > 0 ? positive : negative)"
    }

    var linkDisplayText: String { linkDisplayText(telemetryFailure: nil) }

    /// The link line. A telemetry failure (for example an unreadable layout)
    /// is shown beside the link state so a connected link with empty gauges
    /// is not mistaken for a healthy stream.
    func linkDisplayText(telemetryFailure: String?) -> String {
        let link = linkState.title.uppercased()
        return telemetryFailure == nil ? link : link + " · NO LIVE SIGNALS"
    }

    func linkAccessibilityText(telemetryFailure: String?) -> String {
        (["Link", linkState.title] + [telemetryFailure].compactMap { $0 }).joined(separator: ", ")
    }

    private func tileAccessibility(_ tile: PitWallReadout.Tile) -> String {
        [tile.title, tile.value ?? "no value", tile.freshness.title].joined(separator: ", ")
    }

    private func selectorName(_ selector: String) -> String {
        switch selector {
        case "D": "Drive"
        case "R": "Reverse"
        case "N": "Neutral"
        case "P": "Park"
        case "Shift": "Shifting"
        case "?": "selector, unknown"
        default: selector
        }
    }
}
