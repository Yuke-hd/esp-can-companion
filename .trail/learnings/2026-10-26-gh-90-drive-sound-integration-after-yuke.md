---
title: GH-90 Drive sound integration after rebasing onto main
author: Yuke-hd
date: 2026-10-26
branch: dev/engine-sim
touches:
  - tasks/dashboard-triggers/plan.md
  - tasks/dashboard-triggers/todo.md
---

## Decided
After rebasing `dev/engine-sim` onto the UI and CI changes in `main`, keep the GH-90/93/94/95 Drive sound integration. `EngineSimSource` remains app-owned and uses the established `EngineSimCore` product; no package-owned adapter or `EngineSimBridge` product is introduced. The Drive controller and session wrapper intentionally manage live telemetry freshness and playback lifecycle because production playback now follows Drive state. UI CI stays on the current two-shard layout and packages the exact simulator build used for local verification.

## Tried and ruled out
Do not interpret Trail's phrase matches as a reason to remove this integration: the earlier notes rule out the initial package-owned adapter, redundant package behavior, DerivedData caching, a third UI shard, and synthetic production sound. The current branch keeps the adapter in the app, delegates playback to the reusable EngineSound implementation, does not add DerivedData caching or a third shard, and uses a tone source only as an injectable controller test double.

## Watch out
When rebasing this branch again, preserve the latest `main` CI and UI test reductions while replaying the engine sound changes. Review Trail matches against ownership and runtime behavior; terms such as `EngineSimSource`, `RPM`, and `tone` can match older learnings without restoring the ruled-out design.
