---
title: UI test CI slowness and failures (PRs 102-106)
author: Yuke-hd
date: 2026-10-24
branch: claude/ui-tests-performance-stability-5e953e
cost: { minutes: 2, tokens: 72602 }
---

## Decided
Recommended fixing CI rather than moving UI tests to pre-commit only. Plan: build once (build-for-testing) and shard with test-without-building; boot the simulator before tests (simctl bootstatus -b); retry only for launch stalls (-retry-tests-on-failure -test-iterations 2); keep macOS jobs per run at 5 or fewer; optionally add a demo time-scale launch argument to the in-app fake.

## Tried and ruled out
Treating all UI red runs as flakiness: testSettingsInBothStylesAtLargestText fails every time on iPhone 16/16 Pro landscape at the largest text size (control bottom ~423 > form bottom 395/404) on the #104/#105/#106 stack. It is a real layout bug and passes on iPhone SE.

## Watch out
Real flakes are app launch timeouts ("Timed out while requesting launch progress", "Failed to send signal 19") on loaded macos-15 runners, plus tests that wait on real-time demo data (20-60s timeouts). Each UI shard rebuilds the app (~3 min). The "Sound settings preview" jobs from #104 push a run to 7 macOS jobs, so jobs queue. The "iPhone 16 Pro simulator did not become available" line in logs is the echoed script source, not an error.
