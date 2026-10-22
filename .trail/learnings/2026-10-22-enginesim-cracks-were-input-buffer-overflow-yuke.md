---
title: EngineSim cracks were input-buffer overflow from an unpaced render loop
author: Yuke
date: 2026-10-22
branch: claude/issue-89-4d44c3
cost: { minutes: 25, tokens: 58221 }
touches:
  - Packages/EngineSim/Sources/EngineSimCore/engine_sim_core.cpp
---

## Decided
- engine_sim_render holds physics back while the synthesizer's input latency is at or above its target (and still calls endFrame so the render thread wakes). Without that, offline rendering outruns the audio thread, the synthesizer's input RingBuffer (no overflow check, 44100 samples) wraps and overwrites unread input, heard as periodic cracks (~0.68 s apart). With pacing: 0 bursts at 10 kHz and 5 kHz; simulated time matches audio time (16.14 s for 16 s).

## Tried and ruled out
- Hard clipping (soft limiter added anyway), jitter/air noise, chunk boundaries, dropouts, RPM oscillation: none were the cause. The earlier "5 kHz is worse / 12 kHz clean" finding was an artifact of the unpaced loop (cheaper physics overran more), not of the frequency itself.

## Watch out
- Any caller that drives startFrame/simulateStep faster than playback must pace on getSynthesizerInputLatency(); the upstream app relies on its frame clock. Skipping physics without endFrame deadlocks the render thread.
- Detect cracks with a high-frequency burst detector (first-difference energy per 2 ms vs the +-50 ms median), not hard-clip counts.
