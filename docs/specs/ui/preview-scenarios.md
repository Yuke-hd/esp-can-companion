# UI preview scenarios

Use synthetic controller data to exercise the real app without a board. Named
scenarios are recipes with known starting conditions, events, and expected
results. The [workflow](../../development/ui-verification.md) explains running
them and collecting evidence; [ADR-0001](../../decisions/0001-in-app-fake-for-ui-verification.md)
explains the in-app fake choice.

## Available starting states

These names currently exist in `DemoScenario` and can be passed as
`-DemoScenario <name>`. They use `FakeRadio` and `DemoController`.

| Name | Starting behavior | Useful check |
| --- | --- | --- |
| `notPaired` | No remembered controller; scanning finds a synthetic one. | Discovery and connect journey. |
| `connecting` | Remembered controller is unavailable. | Waiting state without false success. |
| `connected` | Controller running factory configuration; preset uploads and factory revert restart the fake peripheral. | Setup editing, confirmation, send/revert success, and config read-back. |
| `customConfig` | Controller running a custom override. | Confirmed custom configuration presentation. |
| `validationError` | Preset commits receive a synthetic structured controller rejection. | Error code and field presentation; active config remains unchanged. |
| `relinking` | Connection succeeds and then the fake controller powers off. | Waiting to reconnect. |
| `incompatible` | Synthetic controller reports unsupported protocol major. | Clear incompatibility state. |
| `bluetoothOff` | Fake radio reports powered off. | Bluetooth-unavailable presentation. |
| `noAccess` | Fake radio reports unauthorized. | Permission-denied presentation. |

The Pit Wall also has first-launch and large-text previews; these are not extra
launch scenario names. Fake permission states check presentation, not the actual
iOS permission dialog or pairing security. The launched `DemoController` supports
the complete preset send/revert/restart path over `FakeRadio`. These results do
not establish that the real Bluetooth adapter or controller firmware works.

Each process launch constructs a new fake controller from the selected scenario.
Retaining saved phone data does not retain that controller's in-memory state.
For future relaunch checks, define the controller's starting configuration
explicitly as well as the phone's saved working copy.

## Current checks

Pick checks relevant to the change rather than every row for every PR.

- **Successful sync:** launch `connected`, open Setup, edit or choose a bundled
  preset, confirm Send to car, and wait for the restarted controller's active
  config read-back before reporting success.
- **Structured rejection:** launch `validationError`, send a preset and inspect
  the controller error code and field; verify the active config stays unchanged.
- **Factory revert:** launch `connected`, confirm Revert to factory, and check
  the controller restarts with its factory config.
- **Unavailable controller:** use the connection scenarios to check waiting,
  permission, and incompatibility presentation. Setup editing remains available
  after the session is created, but Send to car requires a ready controller.
- **Layout:** use the [drafts](design-reference.md), a small supported phone, and
  larger text for affected screens. Check numeric entry, keyboard dismissal,
  scrolling, and reachability of the fixed Send to car action.

[#18](https://github.com/Yuke-hd/esp-can-companion/issues/18) tracks automated
journeys; it does not imply that those checks run in CI today.

## Live-dashboard follow-up checks

The Pit Wall now decodes a looping synthetic drive sequence from Live signal
frames. [#17](https://github.com/Yuke-hd/esp-can-companion/issues/17) tracks
predictable sequences and stop/resume controls. [#18](https://github.com/Yuke-hd/esp-can-companion/issues/18)
tracks automated UI journeys.

Start small: one named synthetic drive sequence and stop/resume readings. The
fake generates protocol frames; it does not set displayed values or directly
animate the screen. Feed them through the normal notification, decoding,
availability, and screen-update path.

| Recipe | Inputs/events | Expected result |
| --- | --- | --- |
| Draft example | 4,820 RPM, gear 4, 72 km/h, left turn, closed doors, locked, brake unverified, wipers stale. | Comparable appearance; every displayed signal keeps its availability. |
| Short drive | Idle, acceleration, gear changes, indicator activation, deceleration. | Values and indicators update without losing readability or controls. |
| Stop/resume | Stop notifications while the connection remains up, then resume. | After the existing 2-second stall timeout, all signals are unknown; valid frames restore appropriate readings. |
| Missing/unsupported | A signal has no value, is unavailable, or unsupported. | Clear unavailable state; no invented zero or current value. |

Use fixed starting values and predictable event order. Support controlled time
where fast tests need it and realistic pacing for phone review. Stopping the
source must allow the normal stall timeout to run; freezing all app time would
not verify that behavior. Manual controls are optional, not a new framework.

## Agreed working-copy behavior needing persistence work

Local adjustments are allowed, including while disconnected. They do not write
to a controller until an explicit confirmed send. Unsent edits survive app
closure and reopening, are clearly identified, and can be discarded explicitly.

Setup supports choosing and editing bundled presets in an in-memory working copy
across routes, but it does not store changes across app process termination. The
following checks are requirements for
[#19](https://github.com/Yuke-hd/esp-can-companion/issues/19), once persistence is
added, not claims that they pass today:

| Recipe | Expected result |
| --- | --- |
| Edit offline, close, reopen | Restore the same unsent working copy without requiring a controller connection or automatically sending it. |
| Reconnect with a working copy | Preserve edits and separately read what is actually active. |
| Rejected send | Keep the working copy available to correct or retry; active configuration stays separate. |
| Relaunch after interrupted send | Read the controller before claiming success or failure of application; never automatically resend. |
| Explicit discard | Remove the saved unsent changes; ordinary reopening is not a reset. |

Associate saved work with its intended controller when known. An unassigned
bundled-preset draft must not silently become intended for a different controller.
If controller identity or its configuration differs on reconnect, preserve both
sets of information and require explicit review/target selection before sending.
The exact review UI is left to that feature; automatic merging is out of scope.

## Extending a recipe

For a new relevant scenario, record its name, starting controller/configuration,
saved app state, events or user actions, expected results, and evidence needed.
Keep this beside existing scenario code and update this table as checks become
available. Reuse sample data between previews and tests when useful.

Separate a **clean start** from **relaunch with saved state**. Resetting test data
must be explicit and must not erase the data a persistence recipe is testing.
Protocol samples verify software against the documented format; they cannot
establish actual vehicle signal confidence or physical LED behavior.
