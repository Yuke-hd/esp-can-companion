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

## Follow-up: the actual Drive preview still starved with coverage

The constant-source comparison above did not include the app scheme's coverage
instrumentation or changing Drive telemetry. The owner reported continuing
crackles after installing the optimization. A second comparison therefore used
the complete app, its actual Drive view, fake `driveLaps` telemetry, controller,
follower, and player on the same iPhone speaker. Instrumentation lived in a
throwaway app copy; production Swift sources were not changed.

The app's regular test-enabled scheme added `-fprofile-instr-generate` and
`-fcoverage-mapping` to the native `-O2` build, even for a build-only invocation.
The comparison removed only scheme coverage instrumentation. Each run retained
the full Drive UI and captured native/post-follower PCM, per-block target RPM,
throttle, gain, freshness, native render time, and player consumption counters.
The built-in speaker was selected at output volume 0.55 in the coverage-free
run. Thermal state remained fair during both runs.

| Full Drive Debug build | Player interval | Consumed frames | Missing samples | Active native render speed |
| --- | --- | --- | --- | --- |
| Test scheme, coverage enabled | 60.826 s | 2,013,357 | 668,864 | 0.660× |
| Coverage-free preview | 60.814 s | 2,682,221 | 0 | 1.758× |

The coverage-free run included 43.7 seconds with follower gain at one and
changing RPM from 800 to 6,476; its clean result is not just the initial silent
period. Native rendering averaged 3.30 ms per 256-frame block during that active
phase, versus 8.80 ms with coverage. No player failure occurred in either run.
The coverage-enabled run replaced 24.9% of samples across the entire interval
with silence, including its initial silent/stale period.

The initial approximately 17 seconds were stale/unknown telemetry with zero
follower gain. They are not evidence of active audio keeping up. Once live
telemetry enabled ignition, coverage-instrumented native rendering required
about 8.4–9.4 ms per 256 frames, exceeding the 5.805 ms playback budget. Follower
control/fade overhead was about 0.05 ms per block. Native and post-follower PCM
were identical; a detector comparing first-difference energy in 2 ms windows
against the surrounding 50 ms median found no bursts above 10× the local
median. This isolated callback starvation from source/follower discontinuities.

`CANCompanion Audio Preview` is now a separate Debug Run scheme without
coverage instrumentation. Its Run arguments select the fake `driveLaps`
scenario. The existing `CANCompanion` and `CANCompanion Demo` test coverage
settings remain enabled. Generated scheme XML and the clean Audio Preview
native compiler response were checked: `-O2` remains, and the profiling/coverage
flags are absent. No simulation-frequency, timbre, buffer, or player changes
were needed for this follow-up.

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
The first probe isolates constant rendering/playback; the follow-up exercises
the full Drive UI and changing fake RPM. Neither uses live BLE traffic. It does not establish audible sound quality by
listening, or cover every audio route, interruption, and thermal condition.
Repeat the original Drive demo with the Audio Preview Debug scheme on the phone
and listen to continuous engine sound while RPM changes. Existing lifecycle checks remain in
[GH-95 verification](gh-95-drive-audio-lifecycle.md).

The personal screen recording and generated audio were not committed. No
credentials, signing files, device identifiers, or telemetry are included in
this report.
