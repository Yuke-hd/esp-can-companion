# ESP CAN Companion

Contributor and agent documentation: [UI preview and verification](docs/development/ui-verification.md)
and the [documentation index](docs/README.md).

An iOS companion app for ESP-based CAN bus accessory controllers. It talks to any
controller that implements the companion BLE protocol
([spec](https://github.com/Yuke-hd/mazda-can-accessory-controller/blob/main/docs/specs/companion/ble-protocol.md),
originally proposed in [Yuke-hd/mazda-can-accessory-controller#160](https://github.com/Yuke-hd/mazda-can-accessory-controller/issues/160)),
so it is not tied to one vehicle brand.

> Status: early. The app can scan for, pair with, and reconnect to a controller, and
> its Home screen shows the controller's firmware, protocol version and active config.

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
  Sources/CompanionLink/     Protocol client over the BLE link, controller state, demo controller
  Sources/PresetSync/        Bundled presets and the push / revert flow (no UI)
  Sources/CompanionFakes/    In-memory controller for tests and previews
  Sources/DesignSystem/      Dark theme tokens, shared components, preview catalog
```

The app depends on the four package modules. `CompanionProtocol` stays free of
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

## Bluetooth

`BLETransport` has a `ConnectionManager` (observable from SwiftUI) that scans for
the companion service, connects, pairs by reading an encrypted characteristic,
remembers the controller, and reconnects on its own after the controller loses
power or the app is relaunched in the background (state restoration plus the
`bluetooth-central` background mode). It only writes to characteristics of the
companion service.

UUIDs and pairing follow protocol version 1 of the firmware's
[companion BLE spec](https://github.com/Yuke-hd/mazda-can-accessory-controller/blob/main/docs/specs/companion/ble-protocol.md):
the app reads device info and checks the protocol major version before pairing,
and new pairings only work for 120 seconds after the controller's user key is pressed.

`FakeRadio` simulates controllers in memory. The app uses it automatically in the
Simulator, which has no Bluetooth; pass `-FakeController YES` as a launch argument
to use it on a device. Pass `-DemoScenario <name>` to start in another state:
`notPaired`, `connecting`, `connected`, `customConfig`, `relinking`, `incompatible`,
`bluetoothOff` or `noAccess` (see `DemoScenario`). SwiftUI previews use the same scenarios.

## Protocol client

`CompanionProtocol` holds all wire-format knowledge, following the firmware's
[companion spec](https://github.com/Yuke-hd/mazda-can-accessory-controller/tree/main/docs/specs/companion):
device info and the version check, config read-back, chunked upload with commit
and abort, Config status diagnostics, commands, the live signals frame, and
`ControllerConfig` (config schema version 1). `CompanionClient` runs these over a
`CompanionTransport`, so it has no CoreBluetooth dependency and is tested against
an in-memory controller.

Live signal readings keep the controller's availability code. Only code `Fresh` is
fresh, brake is never fresh, and a stream with no frame for 2 seconds reports
every signal as unknown.

`CompanionLink` connects the two. `ConnectionManagerTransport` implements
`CompanionTransport` over `ConnectionManager`, keeping the controller's ATT error
codes. `ControllerSession` owns one `CompanionClient`: on every link change it
clears the client's device info, and on every new connection it reads device
info, Config status and the active config again. `DemoController` answers those
reads on `FakeRadio`.

Golden vectors live in
[`Tests/CompanionProtocolTests/Fixtures/golden-vectors`](Packages/CompanionKit/Tests/CompanionProtocolTests/Fixtures/golden-vectors);
its README says where each file comes from.

## Presets

`PresetSync` ships a few presets in
[`Sources/PresetSync/Presets`](Packages/CompanionKit/Sources/PresetSync/Presets).
Each is a complete, canonical schema version 1 config made from the factory profile
(`factory.json`, a verbatim copy of the firmware's) with a few changes; turn
signals, hazards and the brake light stay exactly as in the factory profile.
`ConfigDescriber` explains each action in plain language.

`PresetSyncModel` pushes a preset or reverts to factory over a `PresetSyncLink`.
The app does not validate presets: the controller does, and the flow shows its
verdict, including the error code and field when it rejects one. A push or revert
counts as done only after the controller restarts and Config status shows the new
config running. Home opens `PresetsView` once a controller is ready, with the
`ControllerSession` as its link. In the Simulator the demo controller refuses
config writes, so a push there ends in an error; the previews use the fake link.

`CompanionFakes` has the in-memory `FakeController` and a `FakePresetSyncLink`
over it, used by the tests and the Presets previews.

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
