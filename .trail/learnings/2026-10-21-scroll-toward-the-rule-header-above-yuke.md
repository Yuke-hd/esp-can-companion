---
title: Scroll toward the rule header above its name field
author: Yuke
date: 2026-10-21
branch: codex/gh-82-83-output-catalog
touches:
  - AppUITests/RuleEditorUITests.swift
---

## Decided
The rule editor toggle sits above its action-name field. To bring the header into view from the expanded editor, repeatedly swipe down toward the top and allow eight attempts for simulator layout differences.

## Tried and ruled out
Reversing scroll direction based on whether the name field is hittable is ambiguous when both controls are outside the viewport, and can move the header farther away.

## Watch out
A UI test can pass locally and fail on a different simulator layout. Use the failing xcresult line to identify the exact scroll assertion, then rerun that specific UI test after changing the helper.
