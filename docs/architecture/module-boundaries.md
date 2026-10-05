# Module boundaries

For this project, SOLID means low coupling and practical replacement of external
dependencies. Keep small agreements between modules; do not create an interface
for every class or make the UI framework replaceable without a concrete need.

## Current responsibilities

| Area | Owns | Boundary |
| --- | --- | --- |
| `App/Sources` | Pit Wall and Setup screens, navigation, and app assembly. | Screens consume typed state and request actions; no BLE byte parsing or alternate demo behavior. |
| `DesignSystem` | Theme, reusable visual components, and their catalog. | Components display supplied state; they do not decide freshness or controller behavior. |
| `BLETransport` | Real/fake radio adapters, connection lifecycle, scheduling, and remembered devices. | `BLERadio` lets `CoreBluetoothRadio` and `FakeRadio` drive the same connection manager. |
| `CompanionProtocol` | Wire messages, codecs, configuration types, and client operations. | Depends on `CompanionTransport`, not CoreBluetooth or SwiftUI. |
| `CompanionLink` | Connection-to-protocol adapter, controller session, demo assembly, and sync-link integration. | Assemble real or fake dependencies here or at app startup, rather than branching in screens. |
| `PresetSync` | Bundled presets, descriptions, and send/revert behavior. | Uses `PresetSyncLink`; no UI or CoreBluetooth dependency. |
| `CompanionFakes` | In-memory controller responses and test/preview sync adapter. | Reuse protocol models and sample data; no screen-specific rendering or real radio access. |

The existing composition is intentionally concrete in places: screens receive a
`ControllerSession`, which uses a `ConnectionManager`. Replacing the radio already
works through `BLERadio`; a second abstraction around the session is not required
merely to claim compliance. `CompanionLink` currently depends on `CompanionFakes`
for demo assembly. Splitting that composition out is future work only if it
solves a real dependency problem.

## Replacement rules

- Select real or fake communication at assembly time. Swapping it should not
  require changes to individual screens or configuration behavior.
- Full-app demos send protocol-shaped reads, writes, and notifications through
  the normal processing path. Small component previews may use supplied display
  state, but do not establish full-app correctness.
- Simulated failures must be normal reported failures. Screens must not contain
  shortcuts such as "demo mode means success."
- Provide predictable timing where repeatable tests need it. Reuse scheduling
  boundaries rather than adding arbitrary sleeps throughout screens.
- When draft persistence is added, keep loading/saving separate from Bluetooth
  and presentation. A small storage interface or injected functions are enough
  to support disk storage in the app and temporary storage in tests.
- Real and fake implementations must honor the same operation/result contract,
  including failure, cancellation, and restart behavior. Share controller
  simulation behavior if an external BLE adapter is added later.

## Configuration and data boundaries

Setup edits an in-memory working copy of a bundled preset. Storage across
relaunches is tracked in [#19](https://github.com/Yuke-hd/esp-can-companion/issues/19).

Editing changes the phone's working copy. Only an explicit confirmed send writes
it to the controller. A working copy, the copy being sent, and configuration
confirmed by read-back are distinct; presenting one as another is a bug.

The controller owns semantic validation. Local format checks can explain input
errors but cannot establish controller acceptance. Saved drafts must not depend
on an active Bluetooth connection. The future persistence behavior is listed in
the [scenario reference](../specs/ui/preview-scenarios.md).

Live readings retain the controller's availability information. The protocol
client owns decoding and stalled-stream handling; visual components display
those results. A demo does not invent measurements unsupported by the protocol
or claim to know which physical LED outputs are active.

## Review questions

1. Can this behavior be exercised without a board through its normal processing?
2. Can a failure scenario be introduced without changing screen code?
3. Does changing storage or communication affect only the relevant adapter and assembly?
4. Are simulated inputs kept separate from real observations and confirmed state?

Review these boundaries as part of the diff and relevant tests. A new dependency
checker or large architecture refactor is not required for this documentation.
