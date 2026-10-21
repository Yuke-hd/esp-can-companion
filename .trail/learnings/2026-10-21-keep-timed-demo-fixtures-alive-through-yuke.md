---
title: Keep timed demo fixtures alive through UI setup
author: Yuke
date: 2026-10-21
branch: codex/gh-82-83-output-catalog
touches:
  - AppUITests/DiscoveredSignalsUITests.swift
  - AppUITests/RuleEditorUITests.swift
  - Packages/CompanionKit/Sources/CompanionLink/DemoScenario.swift
---

## Decided
Timed demo scenarios used by UI tests must keep their valid state long enough for simulator startup, app connection, and navigation to the screen under test. The scenario clock starts when streaming begins, not when the test first inspects the UI, so malformed/stalled transitions need a generous setup window and a matching wait timeout.

## Tried and ruled out
A six-second transition was too short: CI could reach the signal sheet after the valid prefix had already expired. The package behavior was correct; the fixture timing made the UI assertion nondeterministic.

## Watch out
When a scroll gesture must move a specific SwiftUI list, swipe the list scroll view instead of the whole application. Keep enough retries for the header to become hittable and inspect the xcresult when CI disagrees with a local pass.
