import SwiftUI

/// Dark-only design tokens for the companion app.
///
/// The palette is a dashboard look: near-black surfaces, high-contrast text, and
/// one accent. Status colors are reserved for link and device state.
public enum Theme {
    public enum Palette {
        public static let background = ColorToken(hex: 0x0B0D10)
        public static let surface = ColorToken(hex: 0x15181D)
        public static let surfaceRaised = ColorToken(hex: 0x1E2228)
        public static let separator = ColorToken(hex: 0x2A2F37)

        public static let textPrimary = ColorToken(hex: 0xF2F4F7)
        public static let textSecondary = ColorToken(hex: 0x9AA3AF)
        public static let textOnAccent = ColorToken(hex: 0x081018)

        public static let accent = ColorToken(hex: 0x4FC3F7)
        public static let success = ColorToken(hex: 0x4ADE80)
        public static let warning = ColorToken(hex: 0xFBBF24)
        public static let danger = ColorToken(hex: 0xF87171)
    }

    /// SwiftUI colors for use in views.
    public enum Colors {
        public static let background = Palette.background.color
        public static let surface = Palette.surface.color
        public static let surfaceRaised = Palette.surfaceRaised.color
        public static let separator = Palette.separator.color
        public static let textPrimary = Palette.textPrimary.color
        public static let textSecondary = Palette.textSecondary.color
        public static let textOnAccent = Palette.textOnAccent.color
        public static let accent = Palette.accent.color
        public static let success = Palette.success.color
        public static let warning = Palette.warning.color
        public static let danger = Palette.danger.color
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

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 14
        public static let lg: CGFloat = 20
        public static let pill: CGFloat = 999
    }

    /// Type scale built on Dynamic Type text styles so it scales with user settings.
    public enum Typography {
        public static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
        public static let title = Font.system(.title2, design: .rounded).weight(.semibold)
        public static let headline = Font.system(.headline, design: .rounded)
        public static let body = Font.system(.body)
        public static let caption = Font.system(.caption).weight(.medium)
        /// Tabular digits for live readings such as voltages and counters.
        public static let readout = Font.system(.title, design: .monospaced).weight(.semibold).monospacedDigit()
    }
}
