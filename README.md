# ESP CAN Companion

An iOS companion app for ESP-based CAN bus accessory controllers. It talks to any
controller that implements the companion BLE protocol
([spec](https://github.com/Yuke-hd/mazda-can-accessory-controller/blob/main/docs/specs/companion/ble-protocol.md),
originally proposed in [Yuke-hd/mazda-can-accessory-controller#160](https://github.com/Yuke-hd/mazda-can-accessory-controller/issues/160)),
so it is not tied to one vehicle brand.

> Status: early scaffold. The app launches to a placeholder Home screen; Bluetooth
> and the protocol client are not implemented yet.

## Requirements

- macOS with Xcode 16 or newer
- iOS 17 or newer (simulator or device)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Project layout

```
project.yml                  XcodeGen spec; the .xcodeproj is generated, not committed
Config/                      Shared build settings and the local signing override
App/Sources/                 SwiftUI app target (screens and app wiring only)
AppTests/                    App unit tests
Packages/CompanionKit/       Local Swift package
  Sources/BLETransport/      CoreBluetooth link: scanning, connecting, moving bytes
  Sources/CompanionProtocol/ Protocol messages and codecs (no UI, no CoreBluetooth)
  Sources/DesignSystem/      Dark theme tokens, shared components, preview catalog
```

The app depends on the three package modules. `CompanionProtocol` stays free of
CoreBluetooth and SwiftUI so it can be tested against golden vectors on any host.

## Build and run in the Simulator

```sh
xcodegen generate
open CANCompanion.xcodeproj
```

Pick the `CANCompanion` scheme and an iPhone simulator, then Run (⌘R).
Re-run `xcodegen generate` after pulling changes that touch `project.yml` or
add and remove files.

From the command line:

```sh
xcodegen generate
xcodebuild test -project CANCompanion.xcodeproj -scheme CANCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

cd Packages/CompanionKit
xcodebuild test -scheme CompanionKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Theme

The app is dark-only and follows the "Pit Wall" drafts. Tokens live in
[`Theme.swift`](Packages/CompanionKit/Sources/DesignSystem/Theme.swift): palette,
spacing, corner radii, and a Dynamic Type based type scale using system fonts (SF
compressed/condensed for display text, SF Mono for labels). Unit tests check that
text and status colors meet WCAG contrast targets on every surface.

The core components (`Card`, `StatusPill`, `PrimaryButtonStyle`, `SecondaryButtonStyle`) are shown in
[`ComponentCatalog.swift`](Packages/CompanionKit/Sources/DesignSystem/ComponentCatalog.swift).
Open it in Xcode to see them in the preview canvas. Debug builds also link to the
catalog from the Home screen toolbar.

## Install on your own iPhone (development signing)

You do not need a paid Apple Developer account for a personal device build; a
free Apple ID works, but the build expires after 7 days.

1. Add your Apple ID in Xcode → Settings → Accounts.
2. Copy the signing template and fill in your values. The copy is git-ignored.
   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
   - `DEVELOPMENT_TEAM`: your Team ID (shown in Xcode → Settings → Accounts →
     your team, or developer.apple.com → Membership).
   - `APP_BUNDLE_ID`: a bundle identifier unique to you, such as
     `com.yourname.cancompanion`.
3. Run `xcodegen generate`, connect the iPhone, select it as the run destination,
   and Run. Xcode manages the provisioning profile automatically.
4. On the phone, enable Developer Mode (Settings → Privacy & Security) and, for a
   free account, trust your developer certificate under Settings → General →
   VPN & Device Management.

## CI

GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs on a
macOS runner for every pull request and push to `main`. It generates the project,
then builds and runs the package and app unit tests on an iOS Simulator. No
signing is involved.

## Data safety

Never commit vehicle captures, VINs, or anything that identifies a vehicle or
person. Sample and test data must be synthetic. `.gitignore` excludes common
capture formats as a backstop.

## License

MIT. See [LICENSE](LICENSE).
