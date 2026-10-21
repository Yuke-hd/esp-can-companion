---
title: Clarify README installation prerequisites
author: Yuke
date: 2026-10-21
branch: main
touches:
  - README.md
  - docs/README.md
  - docs/development/ui-verification.md
  - docs/development/getting-started.md
---

## Decided
The user-facing README must explain that installing this version requires a Mac and Xcode 16 or later. Bluetooth permission and pairing steps belong in the user guide. These facts are explicitly allowed in README.md. The prior README-audience learning concerns leading with developer commands and protocol internals, not mentioning prerequisites in the installation section.

## Tried and ruled out
An automatic trail check reported README.md as conflicting with the audience learning because it contains installation and connection terminology. The current change follows that learning: it opens with the app's purpose, and places developer commands in docs/development/getting-started.md. The terminology match is a false positive; omitting these requirements would mislead users.

## Watch out
Assess placement and reader purpose when checking the README. Preserve honest installation limitations and actionable connection instructions.
