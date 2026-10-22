---
title: Release initialized engine when synth thread startup fails
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-90-engine-sim-bridge
touches:
  - Packages/EngineSim
---

## Decided
The expanded C factory translates audio-thread startup exceptions into a null handle, so thread-start failure must first destroy the fully initialized simulator and LS V8 engine. The narrow guard around startAudioRenderingThread uses the same normal destruction path, which is safe when the synthesizer thread pointer is null.

## Tried and ruled out
A catch-all returning null alone leaked 133 allocations / 1,058,960 bytes when a standalone probe interposed pthread_create to return EAGAIN. Normal create/destroy leak checks did not cover this exceptional path.

## Watch out
The fork's swift/Tests/check_bridge_leaks.sh now runs both a forty-cycle normal lifecycle probe and a deterministic standalone ThreadStartFailure probe. Keep failure injection isolated from XCTest/system frameworks. Do not broaden the fix into an unrelated builder ownership refactor; thread startup occurs after complete initialization and supports the normal cleanup path.
