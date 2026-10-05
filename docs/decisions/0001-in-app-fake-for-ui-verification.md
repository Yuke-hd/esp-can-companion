# ADR-0001: Use the in-app fake for routine board-free UI verification

Status: Accepted
Date: 2026-10-05
Retrospective: no

## Context

The app and firmware are developed in parallel. UI development and verification
must work without a board, and future coding agents need a repeatable workflow.
The owner reviews on an iPhone. This is an OSS hobby project, so setup and
maintenance should remain small.

The app already has `FakeRadio`, `DemoController`, an in-memory protocol
controller, named `DemoScenario` states, and previews/tests. A moving dashboard
can use synthetic protocol frames through the same application processing;
it does not require real Bluetooth traffic.

An external BLE peripheral simulator would run on a separate device, advertise
the controller's service, and let the iPhone exercise its real Bluetooth path.
It adds radio availability, another running process, advertising/subscription
handling, and platform-specific limitations. These are useful for communication
checks but unnecessary for ordinary UI work.

The owner requested this record after discussing the recommendation to keep the
existing in-app fake as the default and defer the external emulator. This records
that current choice, not a reconstructed motivation for the original fake code.

## Decision

- Use the in-app fake as the default for routine UI previews, phone demos, and
  automated board-free verification. Full-app scenarios exercise real screen and
  application logic with synthetic controller inputs.
- Extend the existing fake and named scenarios as needed. Start moving-dashboard
  work with one predictable sequence and stop/resume readings.
- Do not build or require an external Bluetooth emulator now. Revisit it when
  firmware availability repeatedly blocks Bluetooth integration, communication
  changes require frequent phone checks, or controlled radio reproduction would
  materially simplify debugging.
- Preserve existing replaceable communication boundaries. If an external BLE
  adapter becomes worthwhile, reuse the controller-simulation behavior where
  practical instead of maintaining two independent models. No speculative
  refactor or second adapter is required today.
- Keep UI-fake, real-phone Bluetooth, and board/vehicle results distinguishable.
  Neither type of simulator establishes real firmware compatibility.

## Consequences

Easier:

- Contributors and agents can verify UI in the Simulator without a controller.
- The owner can use fake mode on an iPhone without a nearby Mac advertising BLE.
- Synthetic delays, rejection, missing data, and disconnections are repeatable.
- Existing fake infrastructure remains useful; a second program is not maintained.

Limitations:

- In-app fake checks bypass CoreBluetooth. Real pairing, radio behavior, background
  restoration, and platform Bluetooth behavior still require separate checks.
- Fake behavior can diverge from firmware. Use spec-backed examples and the
  existing golden-vector tests, and validate against hardware when appropriate.
- The moving-data feed, evidence helper, and UI interaction coverage still need
  implementation. Accepting this ADR does not imply those tools already exist.

## Alternatives

- **External BLE emulator only:** exercises real phone Bluetooth, but makes
  ordinary UI verification depend on additional hardware/radio setup and does
  not replace the existing in-process preview/test path.
- **Build both now:** offers complementary coverage but adds maintenance before
  a repeated Bluetooth-testing need has been demonstrated. Keep the option open.
- **Real board only:** blocks UI work on firmware and hardware availability and
  makes controlled failures harder to reproduce. Does not meet board-free development.

## References

- Owner/developer workflow discussion, 2026-10-05: phone review, board-free checks,
  practical low coupling, hobby-project scope, and simulator versus emulator choice.
- [UI verification](../development/ui-verification.md),
  [preview scenarios](../specs/ui/preview-scenarios.md), and
  [module boundaries](../architecture/module-boundaries.md).
- [#2](https://github.com/Yuke-hd/esp-can-companion/issues/2): fake radio and connection layer.
- [#14](https://github.com/Yuke-hd/esp-can-companion/issues/14): live Pit Wall and basic synthetic frames.
- [Apple peripheral-role guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/PerformingCommonPeripheralRoleTasks/PerformingCommonPeripheralRoleTasks.html).
