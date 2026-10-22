---
title: Split GH-90 app adapter from reusable fork controls
author: Yuke
date: 2026-10-22
branch: codex/gh-90-engine-sim-bridge
touches:
  - ".github/workflows/ci.yml"
  - Packages/EngineSim
  - project.yml
  - ".github/actions/setup-engine-sim/action.yml"
  - App/Sources/Drive/EngineSimSource.swift
  - AppTests/EngineSimSourceTests.swift
---

## Decided
During implementation issue #90 was rewritten to clarify package/app ownership. EngineSimCore controls/profile/native lifecycle and tests live in engine-sim-C#4. EngineSoundSource is a minimal neutral reusable protocol prerequisite for engine-sim-C#2; playback remains there. Companion owns App/Sources/Drive/EngineSimSource.swift and its AppTests. This supersedes the earlier learning's proposed package-owned adapter/EngineSimBridge target.

## Tried and ruled out
Do not publish the initial package-owned adapter or an additional EngineSimBridge product: the established EngineSimCore C product is the public control surface and keeps C++ out of app imports. Do not implement player/session/freshness behavior merely to supply the adapter's protocol.

## Watch out
Once the app links EngineSimCore and EngineSound products, app and UI CI must initialize the EngineSim gitlink and only its solver submodule. A reusable setup-engine-sim composite action avoids incomplete checkout in those jobs. Pin-only changes must trigger EngineSim tests and app integration tests. Owner selected original physical sound over a filtered tone; firing-order tests measure honest local order presence and actual RPM, without globally-dominant claims.
