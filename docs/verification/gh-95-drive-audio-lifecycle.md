# GH-95 Drive audio lifecycle verification

## Scope

Drive visibility and scene activity gate playback requests. Inactive scenes,
including screen lock/background transitions, and leaving Drive call the reusable
player's fade/stop path. No audio background mode is added.

The app session adapter applies persisted duck/mix preferences through
`EngineSoundSession.acquire/release`. It acquires the new reference before
releasing the old reference, so the pinned package coordinator remains active
and reasserts the remaining policy. A lock serializes this transition against
player pause/stop on its control queue. All interruption, route, and thermal
events pass to the package unchanged; a retained player is never restarted by a
settings update or telemetry repaint.

## Automated coverage

`DriveEngineSoundControllerTests` covers hidden/inactive Drive, exit,
background/foreground, live policy changes without player restart, failed policy
acquisition retaining the previous policy, explicit off while paused, and event
forwarding. The Simulator-only real-player test uses a fake session to exercise
interruption recovery, critical thermal pause/recovery, route-removal pause, and
explicit off surviving recovery and foregrounding.

Local commands use iPhone 16 / iOS 18.4, UDID
`5F64FF0E-1A6A-471D-B2A0-E83A70920CAC`, Xcode 26.5:

- `xcodegen generate`: passed.
- `git diff --check`: passed.
- Swift frontend parsing of changed sources/tests: passed.
- App tests and CompanionKit tests: started; final results recorded on the PR.
- UI journey and rendered evidence: final result recorded on the PR. No layout
  changes are introduced by this issue.

## Hardware follow-up

No physical-device listening was performed during implementation. On a phone,
with sound enabled in Drive, check a call interruption and permitted recovery,
headphone/Bluetooth route removal, lock/unlock and background/foreground, then
repeat recovery after explicitly disabling sound. Check audible duck/mix with
other audio playing. These checks remain manual validation when hardware is
available; fake-session and Simulator results do not establish hardware audio
behavior.
