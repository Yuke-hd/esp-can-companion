---
title: RuleEditorUITests header scroll direction after catalog section
author: Yuke-hd
date: 2026-10-27
branch: codex/gh-82-83-output-catalog
touches:
  - AppUITests/RuleEditorUITests.swift
---

## Decided
- collapseAndExpandRule scrolls toward the rule header based on its frame (swipeUp when it is below the scroll view, swipeDown when above). With the output catalog section, Setup is long enough that after saving the rule sheet the new rule's header sits below the viewport (y≈3572 in a 787pt view).

## Tried and ruled out
- Swiping down only (and targeting the inner scroll view): deterministic failure, not CI flakiness; it scrolls away from the header.

## Watch out
- Read the diagnostic frames in the assert message before assuming a flake; they showed the header below the viewport.
