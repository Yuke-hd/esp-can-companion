# Debug Drive audio dropout verification

Verified on 23 October 2026. The supplied screen recording showed short bursts
of engine sound separated by long quiet gaps. The app was launched from Xcode
with the Debug configuration.

## Cause and change

`EngineSimCore` inherited Debug's unoptimized C++ build. Its physics and
synthesizer producer could not sustain 44,100 frames per second. The player
remained active, but its real audio callback exhausted the ring and inserted
silence. A test that only confirms some frames were consumed misses this
failure.

The package now compiles only `EngineSimCore` with `-O2` in Debug. Swift app,
player, and UI code retain their normal Debug settings. The simulation remains
at its existing 10 kHz default; buffer size, sample rate, PCM output, and engine
model are unchanged. Release optimization is unchanged.

## Physical device comparison

A disposable SwiftUI host used the app's unchanged `EngineSimSource` and the
package's real `EngineSoundPlayer`, built in Debug with Xcode 26.6 (17F113), for
iPhone 12 Pro running iOS 26.0.1. It used the
LS V8, ignition on, target RPM 1,000/3,000, throttle 0.3, mono PCM16 at 44.1 kHz.
Native rendering produced 88,200 frames in 256-frame blocks at each target.
Fresh sources were used for each render and playback measurement.

Playback held 3,000 RPM. After a two-second warm-up, the harness sampled
`consumedFrameCount` and `underrunCount`, waited twenty seconds, then sampled
both counters again. The reported interval uses actual elapsed wall time.
`underrunCount` counts individual missing samples replaced with silence, not
callback events. Two runs per build distinguish the large improvement from
ordinary timing variation. The device reported nominal thermal state at the
start and end of each run.

| Build/run | 1,000 RPM render speed | 3,000 RPM render speed | Playback interval | Consumed frames | Missing samples |
| --- | --- | --- | --- | --- | --- |
| Baseline 1 | 0.302× | 0.285× | 20.693 s | 255,910 | 656,666 |
| Baseline 2 | 0.283× | 0.268× | 20.896 s | 252,160 | 669,548 |
| Fixed 1 | 1.771× | 1.783× | 21.185 s | 934,214 | 0 |
| Fixed 2 | 1.781× | 1.782× | 20.690 s | 912,576 | 0 |

The baseline callback replaced 71.96% and 72.64% of requested samples with
silence. Both fixed runs had zero missing samples, including startup, and
reported no playback failure. Native throughput rose from 0.27–0.30× to
1.77–1.78× real time, comfortably exceeding the consumption rate in this probe.

The baseline package was copied before editing its manifest. Compiler response
files confirmed effective `-O0` for the baseline and trailing `-O2` for the fixed
Debug native target. The host source was identical between builds. The phone's
free developer profile had reached its three-app limit, so the host reused the
existing disposable engine benchmark app identity. The installed demo app and
personal apps were preserved.

The baseline package commit was `2517ebf`; the fixed package commit was
`56647ca`, published in [engine-sim-C PR #19](https://github.com/Yuke-hd/engine-sim-C/pull/19).

## Regression coverage

The package adds an opt-in performance assertion for its live-sized native
render benchmark, in addition to the existing offline render benchmark. Its
Debug CI benchmark renders three seconds of audio in 256-frame blocks and
requires completion in less than three seconds. This checks the producer's
necessary real-time throughput independently of the playback callback.

The complete fixed app Simulator unit suite passed: 114 tests, zero failures,
16.36 seconds. The baseline focused adapter/controller suite also passed its 21
tests, taking 52.1 seconds; this establishes why merely waiting for output is
insufficient evidence of continuous playback.

## Limits and follow-up

These are synthetic engine signals and measured hardware callback counters.
The probe isolates rendering/playback from the complete Drive UI, live BLE
traffic, and changing RPM. It does not establish audible sound quality by
listening, or cover every audio route, interruption, and thermal condition.
Repeat the original Drive demo with a Debug build on the phone and listen to
continuous engine sound while RPM changes. Existing lifecycle checks remain in
[GH-95 verification](gh-95-drive-audio-lifecycle.md).

The personal screen recording and generated audio were not committed. No
credentials, signing files, device identifiers, or telemetry are included in
this report.
