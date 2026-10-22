---
title: "EngineSim performance: overlap physics and audio; profile on device"
author: Yuke
date: 2026-10-22
branch: claude/issue-89-4d44c3
cost: { minutes: 28, tokens: 51069 }
touches:
  - Packages/EngineSim/Sources/EngineSimCore/engine_sim_core.cpp
  - Packages/EngineSim/Sources/EngineSimCore/include/EngineSimCore.h
  - Packages/EngineSim/Tests/EngineSimCoreTests/LsV8RenderTests.swift
  - ".github/workflows/ci.yml"
---

## Decided
- engine_sim_render overlaps physics (caller thread) with the synthesizer thread; engine_sim_render_synchronous is the serialized comparison. Overlapped is the live-player-representative number: iPhone 12 Pro Release ~1.4-1.55x at 10 kHz, ~1.4x at 5 kHz; synchronous was 0.91x / 1.15x.
- Benchmark on a physical phone through a throwaway host app (SwiftPM test bundles cannot run on device without a host app). Free developer profiles allow only 3 sideloaded apps; the cert must be trusted in Settings first.

## Tried and ruled out
- Trusting a host `sample` (SwiftPM debug config): it showed ConvolutionFilter as the hot spot, but the on-device Release Time Profiler shows GasSystem::flow ~30% and pow ~10%, convolution ~2.5%. Profile the Release build on the device.

## Watch out
- trail check flags NOTICE as "bringing back clang gas system"; that is a false positive, the Mix() ctor patch is intentional and documented there.
- A rev sweep at 4000-5000 rpm clipped (peak 32768) at levelerTarget 20000; the 3000 rpm hold does not.
