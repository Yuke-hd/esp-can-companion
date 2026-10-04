import SwiftUI

/// Dark-only design tokens for the companion app, taken from the "Pit Wall" drafts:
/// near-black surfaces, one racing red for primary actions, and a small set of
/// signal colors that carry meaning (link and freshness, warnings, zones).
public enum Theme {
    public enum Palette {
        public static let background = ColorToken(hex: 0x09090B)
        public static let surface = ColorToken(hex: 0x121317)
        public static let surfaceRaised = ColorToken(hex: 0x1A1C21)
        public static let separator = ColorToken(hex: 0x262930)

        public static let textPrimary = ColorToken(hex: 0xF2F3F5)
        public static let textSecondary = ColorToken(hex: 0x8A8F99)
        /// Small uppercase labels ("CONTROLLER", "LIVE TELEMETRY"). Lower contrast by design;
        /// never use it for values the driver needs to read.
        public static let textTertiary = ColorToken(hex: 0x6C7079)
        /// Stale or unavailable values.
        public static let textDisabled = ColorToken(hex: 0x3A3E47)
        public static let textOnAccent = ColorToken(hex: 0xF2F3F5)

        /// Racing red: primary actions, the brand mark, the active tab, red zone.
        public static let accent = ColorToken(hex: 0xE10600)
        /// Linked, fresh, and live states.
        public static let signalTeal = ColorToken(hex: 0x00D2BE)
        /// Unverified data, pending changes, turn signals.
        public static let signalYellow = ColorToken(hex: 0xFFC800)
        /// Low-RPM shift lights.
        public static let signalGreen = ColorToken(hex: 0x1ED760)
        /// Editing state and fill zones.
        public static let signalBlue = ColorToken(hex: 0x2D7DFF)
        /// Sampled state and priority markers.
        public static let signalPurple = ColorToken(hex: 0xA64DFF)
    }

    /// SwiftUI colors for use in views.
    public enum Colors {
        public static let background = Palette.background.color
        public static let surface = Palette.surface.color
        public static let surfaceRaised = Palette.surfaceRaised.color
        public static let separator = Palette.separator.color
        public static let textPrimary = Palette.textPrimary.color
        public static let textSecondary = Palette.textSecondary.color
        public static let textTertiary = Palette.textTertiary.color
        public static let textDisabled = Palette.textDisabled.color
        public static let textOnAccent = Palette.textOnAccent.color
        public static let accent = Palette.accent.color
        public static let signalTeal = Palette.signalTeal.color
        public static let signalYellow = Palette.signalYellow.color
        public static let signalGreen = Palette.signalGreen.color
        public static let signalBlue = Palette.signalBlue.color
        public static let signalPurple = Palette.signalPurple.color
    }

    /// 4-point spacing scale.
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
    }

    /// The drafts use tight, nearly square corners.
    public enum Radius {
        public static let xs: CGFloat = 2
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 6
    }

    /// Type scale built on Dynamic Type text styles so it scales with user settings.
    ///
    /// The drafts pair a condensed, heavy italic display face with a monospaced label face.
    /// These use the system fonts (SF compressed / condensed and SF Mono) so nothing needs
    /// to be bundled.
    public enum Typography {
        /// Screen titles such as "PIT WALL".
        public static let display = Font.system(.largeTitle).weight(.black).width(.compressed).italic()
        /// Hero readouts such as RPM and gear.
        public static let readoutLarge = Font.system(size: 64).weight(.heavy).width(.compressed).italic().monospacedDigit()
        /// Tile values such as "RELEASED" or "72".
        public static let value = Font.system(.title2).weight(.bold).width(.condensed)
        /// Card and row titles such as "RPM FILL" or "BRAKE".
        public static let headline = Font.system(.headline).weight(.bold).width(.condensed)
        public static let body = Font.system(.body)
        /// Small uppercase labels; pair with `.tracking(Theme.Typography.labelTracking)`.
        public static let label = Font.system(.caption2, design: .monospaced).weight(.medium)
        public static let labelTracking: CGFloat = 1.2
        /// Primary button titles such as "SEND TO CAR".
        public static let button = Font.system(.title3).weight(.heavy).width(.condensed).italic()
    }
}

public extension View {
    /// Styles text as a small uppercase monospaced label, as used for section and field names.
    func themeLabel(_ color: Color = Theme.Colors.textTertiary) -> some View {
        font(Theme.Typography.label)
            .tracking(Theme.Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
