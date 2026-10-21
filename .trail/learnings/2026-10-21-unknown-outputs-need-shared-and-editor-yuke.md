---
title: Unknown outputs need shared and editor support
author: Yuke
date: 2026-10-21
branch: codex/gh-82-83-output-catalog
---

## Decided
OutputBinding must represent and round-trip unknown output types in CompanionKit so firmware and app clients retain forward-compatible data. The app rule editor must also handle that shared unknown case explicitly, keeping unsupported actions read-only and preserving opaque fields during safe edits.

## Tried and ruled out
Treating shared unknown-case support as a problem was too broad. The actual failure mode is stopping at model support without auditing app switches and edit transformations; both layers are required.

## Watch out
A new protocol enum case needs parsing/serialization tests and app-level behavior tests. For output actions, verify opaque large integers survive a permitted rename.
