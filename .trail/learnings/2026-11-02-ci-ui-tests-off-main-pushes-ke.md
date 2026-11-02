---
title: "CI: UI tests off main pushes, daily schedule"
author: Ke
date: 2026-11-02
branch: claude/ci-ui-test-scheduling-96b8e9
cost: { minutes: 1, tokens: 50541 }
touches:
  - ".github/workflows/ci.yml"
  - docs/development/getting-started.md
---

## Decided
- ci.yml `changes` job now has a `ui` output: PRs set it from the path filter, push to main sets false, schedule and workflow_dispatch set true. `ui-build` and `ui-tests` gate on it instead of `companion`. Daily cron is 01:00 UTC (12:00 Sydney in daylight saving, 13:00 in winter).
- "Require UI tests before commit" was read as the PR gate (existing path filter), not a local git hook.

## Tried and ruled out
- Making the UI check required: main has no branch protection (API 404), and changing repo settings is the owner's call, so it was left alone.

## Watch out
- The daily run shares main's ref, so the concurrency group needs the event name or a push to main cancels it.
- Cron runs in UTC and does not follow daylight saving.
