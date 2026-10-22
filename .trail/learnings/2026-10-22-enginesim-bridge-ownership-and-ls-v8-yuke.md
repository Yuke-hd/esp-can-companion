---
title: EngineSim bridge ownership and LS V8 firing spectrum
author: Yuke
date: 2026-10-22
branch: codex/gh-90-engine-sim-bridge
touches:
  - ".github/workflows/ci.yml"
  - Packages/EngineSim
---

## Decided
Keep EngineSound/EngineSimBridge implementation inside engine-sim-C, consumed via Packages/EngineSim gitlink. Main CI must match the exact gitlink path, not only paths with a trailing slash. The source is producer-thread serialized, PCM16 mono 44.1 kHz; ignition-off output mutes queued audio immediately.

## Tried and ruled out
A raw full-sample spectrum after both 0.7s and 2s warmup has strongest engine-order peaks near 62.5/200/125 Hz at requested 1500/3000/5000 RPM; actual crank RPM is correct. Do not disguise this by scanning only the expected firing band or adding a synthetic tone. The explicit dominant-firing acceptance is unresolved pending the owner's sound choice; draft PRs retain a failing acceptance test.

## Watch out
Forty native create/render/destroy cycles initially leaked 920 allocations/15,408,640 bytes. Missing cleanup included synth transfer buffers, jitter histories, cylinder heads, rod journals, displacement scratch arrays, crankshaft links, and the borrowed optimized solver. Fixes report zero allocations leaked with macOS leaks --atExit; the fork has a reproducible swift/Tests/check_bridge_leaks.sh probe. Lifecycle XCTest alone cannot prove absence of native leaks. Root #90 review found no further API/lifecycle blockers; iOS remaining controls are verified separately while pitch remains intentionally failing in the full suite.
