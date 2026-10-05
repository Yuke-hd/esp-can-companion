import Foundation
import SwiftUI
import DesignSystem
import CompanionProtocol
import CompanionLink

// Words and colors the Pit Wall shows, kept apart from the views so unit
// tests can cover them.

extension ConfigSummary.Profile {
    var title: String {
        switch self {
        case .factory: "Factory"
        case .preset(let name): name
        case .custom: "Custom"
        }
    }
}

extension ControllerSession.ActiveConfig {
    /// The profile cell: the config's name, or why there is none.
    var profileTitle: String {
        switch self {
        case .none: "None"
        case .unreadable: "Unknown"
        case .summary(let summary): summary.profile.title
        }
    }

    var configSummary: ConfigSummary? {
        if case .summary(let summary) = self { return summary }
        return nil
    }
}

extension PitWallReadout {
    /// The bus cell. The controller only ever listens on CAN (the firmware
    /// enforces listen-only), so once telemetry has started the bus is
    /// listen-only by construction.
    var busTitle: String {
        switch isTelemetryStarted {
        case true?: "Listen-only"
        case false?: "Not started"
        case nil: "—"
        }
    }

    /// "4,820", or a dash when RPM must not be shown.
    var rpmText: String {
        rpm.map { Int($0.rounded()).formatted() } ?? "—"
    }

    var gearDisplay: String { gear ?? "—" }
    var speedText: String { speedKPH.map(String.init) ?? "—" }

    var gearBox: ReadoutBox {
        ReadoutBox(label: "Gear", value: gearDisplay, freshness: gearFreshness, isShown: gear != nil)
    }

    var speedBox: ReadoutBox {
        ReadoutBox(label: "Km/h", value: speedText, freshness: speedFreshness, isShown: speedKPH != nil)
    }

    var rpmAccessibilityText: String {
        guard let rpm else { return "Engine RPM, no value, \(rpmFreshness.title)" }
        return "Engine RPM \(Int(rpm.rounded())), \(rpmFreshness.title)"
    }
}

extension PitWallReadout.Freshness {
    var color: Color {
        switch self {
        case .fresh: Theme.Colors.signalTeal
        case .unverified: Theme.Colors.signalYellow
        default: Theme.Colors.textTertiary
        }
    }
}

extension PitWallReadout.Tone {
    var color: Color {
        switch self {
        case .normal: Theme.Colors.textPrimary
        case .active: Theme.Colors.signalYellow
        case .calm: Theme.Colors.signalTeal
        case .muted: Theme.Colors.textSecondary
        }
    }
}

extension ConfigSummary.Output {
    /// The output's LED color at full brightness, so a dim night color such
    /// as RGB 0·16·32 still reads as blue. Built-in effects use the turn
    /// signal yellow.
    var swatch: ColorToken {
        guard let color else { return Theme.Palette.signalYellow }
        let top = Double(max(color.red, color.green, color.blue))
        guard top > 0 else { return Theme.Palette.textSecondary }
        return ColorToken(red: Double(color.red) / top, green: Double(color.green) / top, blue: Double(color.blue) / top)
    }

    var kindTitle: String {
        switch kind {
        case .effect: "Effect"
        case .fill: "Fill"
        case .flash: "Flash"
        case .solid: "Solid"
        }
    }

    var accessibilityText: String {
        "\(title), priority \(priority), \(kindTitle)"
    }
}

/// What a boxed readout such as gear or km/h shows, line by line. The view
/// draws exactly these lines, so the freshness label is always on screen,
/// not only in VoiceOver: on a car both values arrive unverified.
struct ReadoutBox: Equatable {
    enum Role: Equatable {
        case label, value, freshness
    }

    struct Line: Equatable, Identifiable {
        var role: Role
        var text: String
        var id: Role { role }
    }

    var label: String
    var value: String
    var freshness: PitWallReadout.Freshness
    var isShown: Bool

    var lines: [Line] {
        [
            Line(role: .label, text: label),
            Line(role: .value, text: value),
            Line(role: .freshness, text: freshness.title),
        ]
    }

    var accessibilityText: String {
        "\(label), \(isShown ? value : "no value"), \(freshness.title)"
    }
}
