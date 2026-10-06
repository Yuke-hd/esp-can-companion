import Foundation
import CompanionLink

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
    var throttleDisplayText: String { "NO SIGNAL" }
    var boostDisplayText: String { "PLACEHOLDER" }
    var throttleAccessibilityText: String { "Throttle, not available" }
    var boostAccessibilityText: String { "Turbo, placeholder, not available" }

    var linkDisplayText: String { linkState.title.uppercased() }

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
