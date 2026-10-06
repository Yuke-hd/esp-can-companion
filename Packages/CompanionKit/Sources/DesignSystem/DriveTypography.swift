import SwiftUI
import CoreText

extension Theme {
    /// Typefaces named by the Drive draft. They are bundled under the SIL Open
    /// Font License (see `Fonts/OFL-*.txt`) and used on Drive only; the rest of
    /// the app keeps the system faces.
    public enum DriveTypography {
        /// Numerals: Barlow Condensed ExtraBold Italic.
        public static func numerals(_ size: CGFloat) -> Font {
            registerFonts()
            return .custom("BarlowCondensed-ExtraBoldItalic", fixedSize: size)
        }

        /// Words such as the profile name: Barlow Condensed Bold Italic.
        public static func display(_ size: CGFloat) -> Font {
            registerFonts()
            return .custom("BarlowCondensed-BoldItalic", fixedSize: size)
        }

        /// Labels and chips: JetBrains Mono.
        public static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            registerFonts()
            return .custom("JetBrains Mono", fixedSize: size).weight(weight)
        }

        /// Registers the bundled faces with the process once. Safe to call repeatedly.
        public static func registerFonts() {
            _ = registration
        }

        private static let registration: Void = {
            let names = [
                "BarlowCondensed-BoldItalic",
                "BarlowCondensed-ExtraBoldItalic",
                "JetBrainsMono-Variable",
            ]
            for name in names {
                guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                    assertionFailure("Missing bundled font \(name)")
                    continue
                }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }()
    }
}
