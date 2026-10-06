import XCTest
import CoreText
@testable import DesignSystem

/// The Drive faces are looked up by name; a typo or failed registration would
/// silently fall back to the system font, so check each name resolves.
final class DriveTypographyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Theme.DriveTypography.registerFonts()
    }

    func testBarlowFacesResolveByPostScriptName() {
        for name in ["BarlowCondensed-BoldItalic", "BarlowCondensed-ExtraBoldItalic"] {
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name)
        }
    }

    func testJetBrainsMonoResolvesByFamilyName() {
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute: "JetBrains Mono"] as CFDictionary
        )
        let matched = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, nil)
        XCTAssertNotNil(matched)
        let family = matched.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
        XCTAssertEqual(family, "JetBrains Mono")
    }
}
