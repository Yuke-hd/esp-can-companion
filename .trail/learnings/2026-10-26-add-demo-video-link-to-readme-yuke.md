---
title: Add demo video link to README
author: Yuke-hd
date: 2026-10-26
branch: dev/engine-sim
cost: { minutes: 1, tokens: 94011 }
touches:
  - README.md
  - tasks/dashboard-triggers/plan.md
  - tasks/dashboard-triggers/todo.md
---

## Decided
Link the YouTube Short from README "Preview / demo" as a clickable img.youtube.com thumbnail plus a text link, without the ?si= tracking parameter.

## Tried and ruled out
Embedding a playable video: GitHub READMEs strip iframes and video tags for external hosts.

## Watch out
The caption is generic because the video content was not watched; refine it if the owner describes the video.
