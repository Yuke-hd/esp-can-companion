---
title: "CI wall time: background simulator boot, Homebrew contention, host package tests"
author: Yuke-hd
date: 2026-10-25
branch: claude/ci-early-sim-boot
cost: { minutes: 33, tokens: 204496 }
touches:
  - ".github/actions/start-simulator/action.yml"
  - ".github/workflows/ci.yml"
  - docs/development/getting-started.md
  - ".github/actions/setup-ios/action.yml"
  - ".github/scripts/select-xcode.sh"
---

## Decided
Jobs start `simctl boot` in the background via `.github/actions/start-simulator` (selects Xcode first, picks the iPhone 16 Pro on the newest iOS runtime by id, writes SIM_UDID and DESTINATION=id=...) and block on `xcrun simctl bootstatus "$SIM_UDID" -b` just before testing. The unit job boots after setup-ios and builds the CompanionKit package tests (`xcodebuild build-for-testing`) during the boot, then `test-without-building`. UI shards skip setup-ios (no project needed for test-without-building; xcbeautify ships with the macos-15 image). Result vs run 40198036827: wall 15m23s -> 14m39s, Unit tests 15m13s -> 14m10s (run 40213957662, one sample).

## Tried and ruled out
Package tests on the macOS host with `swift test`: builds and passes locally (375 tests), but on the 3-vCPU runner timing tests failed in both CI runs (SignalCatalogDiscoveryTests reset/uncancellable-read, testCancellingAnUploadAbortsIt), even when run last on a quiet runner; never failed in 10 simulator runs. Starting the boot before `brew install`: brew took 3-4 min to start (2s normally), cancelling the gain. DerivedData caching and a third UI shard (costs a macOS job).

## Watch out
After bootstatus returns, the first xcodebuild still spends 1.5-2 min before testing while the simulator settles; only a boot started several minutes earlier hides it (13s), which shards can't do while they `needs: ui-build`. The background boot's output must go to a file (nohup ... > file &) or the step waits on it. Runner variance between runs is minutes; compare step logs, not one job total. trail check on a stacked branch needs `--base <parent branch>`.
