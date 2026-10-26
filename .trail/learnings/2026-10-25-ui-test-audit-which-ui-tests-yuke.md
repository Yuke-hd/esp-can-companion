---
title: "UI test audit: which UI tests duplicate unit coverage"
author: Yuke-hd
date: 2026-10-25
branch: claude/ui-tests-audit-d211dc
cost: { minutes: 3, tokens: 94820 }
---

## Decided
Audit of the 18 UI tests (last green main run: ~922s of UI test time over 3 shards). Five can be dropped because package/app unit tests already cover them: testDriveGMeterShowsNoDataForLayout1Controller, testDriveBrakePressureRisesDuringDemoLap, testDriveShowsNotLinkedStateWithoutTelemetry, testPartialRecordsExpireIndependentlyWhilePeerIsFresh, testMalformedValidPrefixDoesNotKeepValuesLive. Trim testUnavailableScenariosShowNoDiscoveredValues (three launches, 88s) to one or two scenarios, and merge the two Drive navigation tests. That gives about 650s total, which fits in 2 shards.

## Tried and ruled out
Dropping the RuleEditor UI tests: they guard view-lifecycle commits in SetupRulesView (focus loss, onDisappear, the isEdited guard) that unit tests cannot reach. Dropping testDriveReceivesTelemetryAfterLeavingLivePitWall: it is the only coverage of the dashboard notifier handoff fix from #76.

## Watch out
Per-test UI durations appear in `gh run view <id> --log` as "✔ testName (N seconds)" lines, not as XCTest "Test Case passed" lines. Shards are dealt round-robin by sorted test name, so removing tests reshuffles the shards.
