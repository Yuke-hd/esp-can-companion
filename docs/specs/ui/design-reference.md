# UI design reference

The owner supplied "Mazda Accent Lights – Companion App Drafts" and its direction
overview during the workflow discussion. These unchanged image copies make the
reference available to future contributors and agents without personal paths.
The app remains controller/vehicle-brand agnostic; draft branding does not change
that scope.

| Draft | Role |
| --- | --- |
| [00 Direction](reference/00-direction.png) | Overall visual language, color meanings, type, and shared elements. |
| [01 Pit Wall](reference/01-pit-wall.png) | Home dashboard appearance. Basic implementation is tracked in [#14](https://github.com/Yuke-hd/esp-can-companion/issues/14). |
| [02 Setup](reference/02-setup.png) | Intended presets, local adjustments, and explicit Send to car. Main currently has preset selection; working-copy editing exists only in local unmerged work. |
| [03 Strip](reference/03-strip.png) | Future zone-map direction; not an implemented feature commitment. |
| [04 Drive](reference/04-drive.png) | Landscape, read-only dashboard direction; the initial Motorsport implementation is tracked in [#25](https://github.com/Yuke-hd/esp-can-companion/issues/25). |
| [05 Drive — Eva style](reference/05-drive-eva.png) | Alternative Drive exploration; not a second required theme. |

## Appearance to preserve

- Dark pit-wall look, strong hierarchy, large live values, and compact status cards.
- Race red for action/brake, teal for live/OK, yellow for turn/warning, purple for
  high RPM, blue for fill/information, and carbon-colored surfaces.
- Preset rings, light-strip illustration, RPM bar, small corners, and fine borders.
- Visible freshness, with text or symbols as well as color. Stale or unknown
  telemetry clears to placeholders. By owner direction, Drive shows no freshness
  words: a value that is not current clears to a dash, and accessibility labels
  still state its freshness.
- Drive's monitoring view is landscape and read-only. The Motorsport variant is
  the initial implementation; alternative visual variants remain future work.

## Adaptation and limits

The draft names Barlow Condensed Bold Italic and JetBrains Mono. Drive bundles
both (SIL Open Font License, under `DesignSystem/Fonts`) through
`Theme.DriveTypography`. The other screens still use system-font
approximations until an app-wide migration is agreed; explain meaningful
differences in verification evidence.

Drive omits the draft's bottom status strip by owner direction. Brake and turn
already show on the gauges and arrows; only the link state remains, as a quiet
line under the gear. Doors, hazard and profile stay on Pit Wall.

Layout must accommodate supported phone sizes and larger text. Preserve intent
rather than fixed image coordinates: wrapping, scrolling, and rearranging are
appropriate when they keep information readable and controls reachable.

Drafts show moments, not every state. Verify loading, missing data, failure, and
recovery when affected. A label such as "Linked" cannot imply all readings are
fresh. Brake cannot be presented as fresh under the current protocol. Stale or
unknown readings must not be presented as current numeric values.

Boost and throttle/brake percentages in the Drive drafts are placeholders not
provided by the current live-signal model. The controller does not report actual
live/idle LED output status, so the draft's output stack cannot claim it. Any
future simulated lighting illustration must be identified as expected behavior,
not physical-output feedback. "Valid config" cannot imply controller acceptance
before the controller validates it.

An inspected screenshot from the actual app can serve as the visual reference
for subsequent changes. Keep the reason for intentional deviations visible; a
draft image is not an exact pixel-comparison baseline.
