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

    /// Small (11 pt) label text: every color passed to `themeLabel()` needs WCAG AA
    /// for normal text on every surface.
    func testSmallLabelTextMeetsAA() {
        let labelColors = [P.textTertiary, P.textSecondary, P.signalTeal, P.signalYellow,
                           P.signalGreen, P.accentText, P.signalBlueText]
        for color in labelColors {
            for surface in surfaces {
                XCTAssertGreaterThanOrEqual(color.contrastRatio(against: surface), 4.5)
            }
        }
    }

    /// Status pill labels sit on a tinted fill, which is lighter than the bare surface.
    func testStatusPillTextMeetsAAOnItsFill() {
        let statuses: [StatusPill.Status] = [.neutral, .live, .pending, .editing, .alert]
        for status in statuses {
            for surface in surfaces {
                let fill = status.tint.blended(over: surface, opacity: StatusPill.fillOpacity)
                XCTAssertGreaterThanOrEqual(status.text.contrastRatio(against: fill), 4.5, "\(status)")
            }
        }
    }

    /// Saturated signal colors are for dots, borders, bars, and large bold values, so
    /// they need the 3:1 WCAG ratio for non-text UI and large text.
    func testIndicatorColorsMeetNonTextContrast() {
        let colors = [P.accent, P.signalTeal, P.signalYellow, P.signalGreen, P.signalBlue, P.signalPurple]
        for color in colors {
            for surface in surfaces {
                XCTAssertGreaterThanOrEqual(color.contrastRatio(against: surface), 3)
            }
        }
    }

    /// The primary button title is 20 pt heavy, which is large text under WCAG (3:1).
    func testTextOnAccentMeetsLargeTextContrast() {
        XCTAssertGreaterThanOrEqual(P.textOnAccent.contrastRatio(against: P.accent), 3)
    }
}
