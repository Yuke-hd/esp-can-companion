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
- ci.yml `changes` job has a `ui` output that is true only for `schedule` and `workflow_dispatch`; `ui-build` and `ui-tests` gate on it, so no commit (PR or push to main) runs UI tests in CI. Daily cron is 01:00 UTC (12:00 Sydney in daylight saving, 13:00 in winter).
- First version ran UI tests on PRs via the path filter, and `.github/` in that filter made this very PR run them. The owner wanted no commit to trigger them, so the filter no longer feeds `ui`.
- "Require UI tests on changed code before commit" is a local rule: added to AGENTS.md, not a git hook.

## Tried and ruled out
- Making the UI check required: main has no branch protection (API 404), and changing repo settings is the owner's call, so it was left alone.

## Watch out
- The daily run shares main's ref, so the concurrency group needs the event name or a push to main cancels it.
- Cron runs in UTC and does not follow daylight saving.
