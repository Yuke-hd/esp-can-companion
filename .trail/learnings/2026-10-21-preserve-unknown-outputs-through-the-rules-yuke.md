---
title: Preserve unknown outputs through the rules editor
author: Yuke
date: 2026-10-21
branch: codex/gh-82-83-output-catalog
---

## Decided
Unknown output actions need explicit handling in the app's rule editor as well as in the shared CompanionKit model. Keep these actions read-only in effect controls, and preserve their opaque fields when a name is edited.

## Tried and ruled out
Relying only on the shared model's unknown-case support is insufficient: exhaustive app switches must handle the new case, and generic editing controls can otherwise drop fields they do not understand.

## Watch out
When adding a new OutputBinding case, inspect app-facing switches and editor transformations in addition to package parsing/serialization. Keep a regression test that renames an unknown action while retaining a large integer opaque field.
