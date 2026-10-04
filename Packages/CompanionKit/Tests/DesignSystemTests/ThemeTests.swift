import XCTest
@testable import DesignSystem

final class ThemeTests: XCTestCase {
    private typealias P = Theme.Palette
    private let surfaces = [P.background, P.surface, P.surfaceRaised]

    func testHexParsing() {
        let token = ColorToken(hex: 0xFF8000)
        XCTAssertEqual(token.red, 1, accuracy: 0.0001)
        XCTAssertEqual(token.green, 128.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(token.blue, 0, accuracy: 0.0001)
    }

    func testContrastRatioBounds() {
        let black = ColorToken(hex: 0x000000), white = ColorToken(hex: 0xFFFFFF)
        XCTAssertEqual(black.contrastRatio(against: white), 21, accuracy: 0.01)
        XCTAssertEqual(white.contrastRatio(against: white), 1, accuracy: 0.0001)
    }

    /// Values the driver reads must stay legible at a glance: WCAG AAA for primary
    /// text and AA for secondary text, on every surface.
    func testTextContrastOnSurfaces() {
        for surface in surfaces {
            XCTAssertGreaterThanOrEqual(P.textPrimary.contrastRatio(against: surface), 7)
            XCTAssertGreaterThanOrEqual(P.textSecondary.contrastRatio(against: surface), 4.5)
        }
    }

    /// Tertiary labels and signal colors are used for uppercase labels, large bold
    /// values, and indicator graphics, so they need at least the 3:1 WCAG ratio for
    /// large text and non-text UI.
    func testLabelAndSignalColorsMeetLargeTextContrast() {
        let colors = [P.textTertiary, P.accent, P.signalTeal, P.signalYellow,
                      P.signalGreen, P.signalBlue, P.signalPurple]
        for color in colors {
            for surface in surfaces {
                XCTAssertGreaterThanOrEqual(color.contrastRatio(against: surface), 3)
            }
        }
    }

    func testTextOnAccentIsReadable() {
        XCTAssertGreaterThanOrEqual(P.textOnAccent.contrastRatio(against: P.accent), 4.4)
    }
}
