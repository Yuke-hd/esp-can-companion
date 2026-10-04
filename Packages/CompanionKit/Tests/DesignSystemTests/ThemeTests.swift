import XCTest
@testable import DesignSystem

final class ThemeTests: XCTestCase {
    private typealias P = Theme.Palette

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

    /// Text must stay readable at a glance in a car: WCAG AAA for primary text,
    /// AA for secondary text, on every surface it can sit on.
    func testTextContrastOnSurfaces() {
        for surface in [P.background, P.surface, P.surfaceRaised] {
            XCTAssertGreaterThanOrEqual(P.textPrimary.contrastRatio(against: surface), 7)
            XCTAssertGreaterThanOrEqual(P.textSecondary.contrastRatio(against: surface), 4.5)
        }
    }

    func testStatusColorsAreVisibleOnSurface() {
        for status in [P.accent, P.success, P.warning, P.danger] {
            XCTAssertGreaterThanOrEqual(status.contrastRatio(against: P.surface), 4.5)
        }
    }

    func testTextOnAccentIsReadable() {
        XCTAssertGreaterThanOrEqual(P.textOnAccent.contrastRatio(against: P.accent), 4.5)
    }
}
