---
title: Rebasing PR 85 output catalog onto main after UI test pruning
author: Yuke-hd
date: 2026-10-27
branch: codex/gh-82-83-output-catalog
touches:
  - ".github/scripts/ui-test-shard.sh"
---

## Decided
- Rebased codex/gh-82-83-output-catalog onto main instead of merging. Conflicts were only in UI tests: main (#109/#110) deleted testMalformedValidPrefixDoesNotKeepValuesLive and the large-text/brake-pressure drive tests, so those PR-side edits were dropped; RuleEditorUITests keeps main's `toggle.tap(until:)` helper plus the PR's diagnostic assert message and `scrollView.swipeDown()`.

## Tried and ruled out
- Running UI tests via `-scheme CANCompanion -only-testing:CANCompanionUITests/...` fails: UI tests live only in the "CANCompanion UI Tests" scheme now.

## Watch out
- CI is 2 UI shards now (was 3); shard assignment comes from .github/scripts/ui-test-shard.sh.
