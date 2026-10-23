# UI preview and verification

Developers and coding agents should be able to verify UI work without a board.
Use the actual SwiftUI screens with the in-app fake, as decided in
[ADR-0001](../decisions/0001-in-app-fake-for-ui-verification.md). The owner can
review the same behavior on an iPhone; agents normally use the Simulator.

This is an OSS hobby project. Start with the existing tools and checks relevant
to the change. A custom test platform, full device matrix, external Bluetooth
emulator, or automatic screenshot comparison is not a prerequisite.

## What exists today

- Simulator launches use `FakeRadio` automatically. On a phone, Xcode launch
  arguments can select the same in-memory controller.
- `DemoScenario` supplies connection and active-configuration starting states.
  The launched demo currently refuses uploads and factory-revert commands.
  Successful send/restart behavior exists in preset previews and sync tests.
  Full-app send/restart, Setup editing, and the `validationError` scenario exist
  only in local unmerged work; they are not available on main or included here.
- SwiftUI previews and `ComponentCatalog` support quick appearance checks.
- App and package tests check logic and simulated controller interactions.
- CI runs these tests. It does not currently tap through screens or collect
  rendered UI evidence.

Available scenarios and planned checks are listed in the
[scenario reference](../specs/ui/preview-scenarios.md). In particular, a complete
moving dashboard and saved drafts across app relaunches need further work.

## Contributor and agent workflow

1. Identify the affected screen, user actions, expected results, and relevant
   [design reference](../specs/ui/design-reference.md). A short checklist is enough.
2. Start a named fake scenario with known data. Record the scenario and whether
   saved app state is retained or reset. Do not depend on a real board.
3. Exercise the real controls: taps, scrolling, numeric entry, keyboard dismissal,
   navigation, and confirmations as relevant. Include a meaningful failure or
   recovery path when the change affects one. Previews alone are insufficient for
   a multi-screen journey.
4. Inspect the rendered screen against the design. For layout changes, check one
   small supported phone and larger text as well as the usual phone size. Check
   important text remains readable, actions reachable, and content scrollable.
   Check screen-reader labels and reading order when affected.
5. Run relevant existing tests; add behavior coverage for meaningful new logic.
   A layout-only adjustment does not need a test that merely repeats its code.
6. Include screenshots and a short verification report with the change. Add a
   short recording only when transitions or movement cannot be explained by stills.

A successful build is not UI verification. Inspect images, do not merely create
them. Images must come from the implemented app; the draft is the reference.
Use outcome-based waits in automated interaction tests, such as waiting for a
confirmation to appear, rather than arbitrary sleeps. A screenshot alone does
not prove that a draft persisted or a configuration was accepted.

If a check is unavailable, report exactly what remains unverified. Use the
manual workflow while tooling is incomplete; do not call missing tooling a pass.

## Preview on a phone

Follow [development signing](getting-started.md#install-on-your-own-iphone-development-signing)
in the build and development guide. In Xcode, edit the `CANCompanion` scheme's
Run action, under Arguments Passed On Launch. Add these four separate enabled entries:

```text
-FakeController
YES
-DemoScenario
connected
```

Use a scenario name from the reference. `DemoScenario` currently selects a fake
session directly; `FakeController` is also useful by itself for the default
unpaired demo. Run from Xcode after changing arguments. Do not assume tapping the
installed app icon later supplies the same launch arguments. Keep a separate
local demo scheme if convenient; persist shared scheme changes in `project.yml`,
not the generated project. No in-app picker is required for the first workflow.

Fake operation does not need a Bluetooth connection to a Mac or board. Avoid
confusing fake results with controller observations; a visible demo indicator is
a tracked gap. For actual board checks, remove both arguments and use the normal
device build.

## Preview and capture in the Simulator

For manual work, generate the project, open it, select an iPhone Simulator and
Run. Configure launch arguments as above. Open `HomeView.swift` or
`ComponentCatalog.swift` for their Xcode previews.

For agents or command-line work, run from the repository root:

```sh
xcodegen generate
xcrun simctl list devices available
```

Choose an available iPhone UDID from that list. Replace `<UDID>` below; use your
configured `APP_BUNDLE_ID` if it differs from the default shown. A temporary
directory keeps generated evidence and build products out of source control.

```sh
preview_simulator_id='<UDID>'
preview_bundle_id='com.example.cancompanion'
preview_output=$(mktemp -d /tmp/esp-can-preview.XXXXXX)
xcrun simctl bootstatus "$preview_simulator_id" -b
xcodebuild build -project CANCompanion.xcodeproj -scheme CANCompanion \
  -destination "id=$preview_simulator_id" \
  -derivedDataPath "$preview_output/build" CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$preview_simulator_id" \
  "$preview_output/build/Build/Products/Debug-iphonesimulator/CANCompanion.app"
xcrun simctl launch --terminate-running-process "$preview_simulator_id" \
  "$preview_bundle_id" -FakeController YES -DemoScenario connected
```

Interact with the app using Simulator or an available UI-control tool. Once the
expected state is visibly reached, capture it:

```sh
xcrun simctl io "$preview_simulator_id" screenshot "$preview_output/connected.png"
```

`simctl launch` and `screenshot` do not tap controls or verify expectations.
An agent needs a UI-control tool or an implemented UI test for interaction checks;
otherwise it must report those checks as unverified. Use descriptive filenames
for subsequent screenshots and retain the output path in the report.

Relaunching terminates the app process but retains its saved data. A persistence
check must keep that data. For a clean-start check, use a disposable test
installation: uninstalling the app removes its saved data. Never erase a whole
personal Simulator as a routine reset. The planned helper will make reset versus
retain explicit; no dedicated reset command exists today.

## Drive engine sound settings

For listening, generate the project and select the **CANCompanion Audio Preview**
scheme before building or running. Its Debug Run action selects the fake
`driveLaps` scenario. This scheme builds the app without code coverage; the
existing app test schemes retain coverage. The native simulation must meet an
audio deadline, and coverage instrumentation can make even its optimized Debug
build slower than playback. Use the test schemes for automated coverage, then
use Audio Preview for listening and audio timing checks.

For a command-line phone build, use your normal local signing configuration:

```sh
xcodebuild build -project CANCompanion.xcodeproj \
  -scheme "CANCompanion Audio Preview" -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/can-audio-preview
```

Launching through Xcode applies the scheme's fake-controller arguments. A
separate device launch must pass `-FakeController YES -DemoScenario driveLaps`
explicitly; tapping the installed icon does not restore launch arguments.

Sound is off by default. In either Drive style, open the speaker control to
show Engine sound settings. Toggle sound on, then dismiss the sheet and use
`driveLaps` to check that playback follows RPM. Exit Drive to stop playback;
reenter to check a fresh start. Sound and “Lower other audio while playing”
preferences persist across launches with `@AppStorage`. The latter defaults on;
GH-94 exposes it to the controller, while live audio-session policy application
belongs to GH-95. The engine display remains LS V8 until GH-96 adds selection.
The earlier `-EngineSound YES` gate is removed; use the settings control.

Use `stalled` to check unknown RPM and fading to silence. The reusable follower
also expires RPM after 0.5 seconds without a new typed RPM record, even while
unrelated packets keep arriving. Verified and unverified RPM are mapped
separately; unavailable, stale, disconnected, or untimestamped RPM cannot keep
audio live. Unsupported legacy telemetry remains silent. Accelerator input
uses the readout's normalized fraction, with the reusable follower deriving
throttle when that input is unavailable.

App tests inject `ToneSource` and a monotonic clock to check neutral targets,
PCM silence, expiry, preferences, and source release. A Simulator test uses the
real player to require callback frame consumption and release after stop.
`EngineSoundUITests` checks preference persistence without launch-argument
preference overrides and captures both styles' settings at accessibility XXXL.
The CI settings preview matrix runs that screenshot journey on iPhone 16 and
SE (3rd generation); inspect the top and scrolled screenshots for readable
labels and reachable controls.

Inspect playback startup logs as well as test results. UI movement assertions
alone do not establish audible output. Startup failure is logged under the
`DriveSound` category. Keep Simulator recording/listening evidence separate from
physical-device or vehicle validation.

## Tests and evidence

Run the relevant app or package checks on the same selected Simulator:

```sh
xcodebuild test -project CANCompanion.xcodeproj -scheme CANCompanion \
  -destination "id=$preview_simulator_id" CODE_SIGNING_ALLOWED=NO
```

UI tests (navigation, rotation, on-screen layout and demo readouts) are in a
separate scheme because they take a few minutes:

```sh
xcodebuild test -project CANCompanion.xcodeproj -scheme "CANCompanion UI Tests" \
  -destination "id=$preview_simulator_id" CODE_SIGNING_ALLOWED=NO
```

For package changes, run from `Packages/CompanionKit`:

```sh
xcodebuild test -scheme CompanionKit-Package \
  -destination "id=$preview_simulator_id" CODE_SIGNING_ALLOWED=NO
```

These are existing unit/integration tests, not a substitute for interacting with
the rendered app. Review relevant CI results before calling a PR ready.

A report can be this small:

```text
Change: Preset send-error presentation
Revision: <commit>; working-tree changes: <brief description, if any>
Environment: <Xcode version>, <iOS runtime>, <phone model>, <text size>
Scenarios/state: connected; clean start
Actions/results: opened Presets, selected a preset, confirmed Push to controller;
checked the unsupported-operation error and unchanged active configuration
Tests: <commands and actual results>
Evidence: <screenshots; recording only if useful>
Gaps: <unverified checks and intentional differences from the draft>
```

Use synthetic data. Never commit identifying vehicle captures or personal data.
Fake-on-phone results check phone UI behavior; neither those nor Simulator
results establish real Bluetooth pairing, firmware compatibility, or vehicle
behavior. Report board/bench results separately when communication changes need them.

## Small tooling backlog

The first helper should wrap the current commands: explicit Simulator, named
scenario, clear state policy, screenshots, and enough environment details to
repeat the run. It should not implement a second app or scenario engine.

- Repeatable Simulator launch/capture helper: [#16](https://github.com/Yuke-hd/esp-can-companion/issues/16).
- Predictable live readings and stop/resume: [#17](https://github.com/Yuke-hd/esp-can-companion/issues/17); basic dashboard
  wiring remains [#14](https://github.com/Yuke-hd/esp-can-companion/issues/14).
- A few automated UI journeys and useful CI evidence: [#18](https://github.com/Yuke-hd/esp-can-companion/issues/18).
  Success/restart and structured-rejection journeys need full-app fake support
  first; that support currently exists only in local unmerged work.
- A clear fake-session indicator: [#20](https://github.com/Yuke-hd/esp-can-companion/issues/20).
- Saved offline working copies: [#19](https://github.com/Yuke-hd/esp-can-companion/issues/19); this is product work,
  exercised by the workflow, not a prerequisite for verifying existing screens.

Add a phone scenario picker only if launch arguments become inconvenient.
Automatic image comparisons, broad device matrices, and an external BLE
emulator remain deferred.
