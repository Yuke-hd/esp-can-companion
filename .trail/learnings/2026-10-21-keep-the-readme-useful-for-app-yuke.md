---
title: Keep the README useful for app users
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
The root README should explain CAN Companion in plain language for people who want to use the app: compatible hardware, installation requirements, first pairing, screen purposes, sending a setup, and troubleshooting. Keep developer commands and implementation details in docs/development/getting-started.md and link there.

## Tried and ruled out
Leading with Xcode requirements, package layout, and Bluetooth protocol internals makes the entry point difficult for nontechnical users. Do not imply that an easy installation route exists when only development installation is documented.

## Watch out
Keep moved-document links and anchors working, especially the phone-signing link in UI verification. Older documentation can lag implemented screens; check user-facing names and behavior against the current source before claiming that a feature is available or still a placeholder.
