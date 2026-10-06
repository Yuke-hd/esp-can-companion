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

    static let off = MotorsportSignals()

    init() {}

    init(frame: LiveSignalFrame, readout: DriveReadout) {
        let turn = readout.turn.freshness.showsValue ? frame.turnState.value : nil
        let hazard = readout.hazard.freshness.showsValue && frame.hazardRequest.value == true
        leftLit = hazard || turn == .known(.left) || turn == .known(.hazard)
        rightLit = hazard || turn == .known(.right) || turn == .known(.hazard)
        brakePressed = readout.brake.freshness.showsValue ? frame.brakePressed.value : nil

        guard readout.gearFreshness.showsValue, readout.selectorFreshness.showsValue,
              let position = frame.selectorPosition.value else { return }
        switch position {
        case .known(let known): selector = known
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
    // Throttle and boost have no layout v1 signal. Their wording follows the
    // readout's placeholder tiles, so a future signal changes it in one place.
    var throttleDisplayText: String {
        throttle.freshness == .unsupported ? "NO SIGNAL" : throttle.freshness.title.uppercased()
    }
    var boostDisplayText: String {
        boost.freshness == .unsupported ? "PLACEHOLDER" : boost.freshness.title.uppercased()
    }
    var throttleAccessibilityText: String { ["Throttle", throttle.freshness.title].joined(separator: ", ") }
    var boostAccessibilityText: String { ["Turbo, placeholder", boost.freshness.title].joined(separator: ", ") }

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
