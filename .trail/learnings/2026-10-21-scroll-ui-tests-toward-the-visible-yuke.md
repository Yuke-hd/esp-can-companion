---
title: Scroll UI tests toward the visible anchor
author: Yuke
date: 2026-10-21
branch: codex/gh-82-83-output-catalog
touches:
  - AppUITests/RuleEditorUITests.swift
---

## Decided
When an XCUITest scrolls to a nested rule header, use the visible action-name field as an anchor: swipe down when the name field is visible and the header above it is not, otherwise swipe up toward the target. Allow enough scroll attempts for simulator layout variation.

## Tried and ruled out
A fixed four-swipe downward loop can leave a rule header just outside the viewport in CI even though the same test passes locally.

## Watch out
Check the exact source line in the xcresult before changing app behavior for a UI shard failure. Re-run the specific UI test after adjusting its navigation helper.
